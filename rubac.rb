#!/usr/bin/ruby
#
# == Synopsis 
#   A ruby backup front-end powered by rsync that can save
#   multiple backup profiles between uses in an sqlite database
#
# == Usage 
#   rubac [options]
#
#   For help use: rubac -h
#
# == Options
#   -G, --global          Apply excludes, options etc., to global profile
#   -P, --profile[=NAME]  Apply options only to named backup profile (default is rubac)
#   -D, --data_dir[=PATH] Database directory 
#
#   -c, --client[=HOST]   Client to backup (default is local backup)
#   -i, --include=PATH    Include path, comma separate multiple paths
#   -x, --exclude=PATH    Exclude path, comma separate multiple paths
#   -d, --dest=DEST       Local destination path (eg., /mnt/backup)
#   -m, --mail=EMAIL      Notification email, comma separated list
#   -o, --opts=OPTS       Extra rsync options
#
#   -T, --TMP=PATH        Temporary directory for logging, etc (default is /var/log/rubac)
#   -l, --log[=NAME]      Name of log file, (default is profile.%run_date%.log)
#   -s, --syslog          Use syslog for logging [??]
#
#   -t, --list            List the includes, excludes, etc., for the named profile
#   -F, --full            Perform full backup (overwrites rubac.0)
#   -I, --incremental[=N] Number of incremental backups (default is 5)
#   -n, --dry-run         Perform a trial run of the backup
#   -R, --run             Run specified profile
#
#   -H, --history         Backup history
#   -h, --help            Displays help message
#   -v, --version         Display the version
#   -q, --quiet           Output as little as possible, overrides verbose
#   -V, --verbose         Verbose output
#
# == Examples
#
#   Setup and use a default backup
#
#   rubac -G -o "--delete-excluded"
#   rubac -G --data_dir=/etc/rubac
#   rubac -i "/home/steeve,/home/lissa,/home/etienne" -x "*/.gvfs/"
#   rubac -x "*/.thumbnails/,*/.thunderbird/*/ImapMail/,*/.beagle/"
#   rubac -m backupadmin@mail.host
#   rubac -l /var/log/rubac
#   ...
#   rubac --run
#
#   List then backup client esme using the esme profile
#   rubac -c esme -P esme --list
#   rubac -c esme -P esme --run
#
#   Should one be able to specify a client using rsync notation,
#
#   rubac -c donkey -i "/home/steeve,/home/lissa,/home/etienne" -x "*/.gvfs/"
#   rubac -i "donkey:/home/steeve,donkey:/home/lissa,donkey:/home/etienne"
#
#   Each include path should probably include a client (unless local) so
#   the host should be part of the includes database table.
#
# == Environment Variables ==
#
#   RUBAC_DATADIR - set the database directory
#   RUBAC_PROFILE - set the backup profile to use
#   RUBAC_CLIENT  - set the client to use
#   RSYNC_RSH     - ssh command string, defaults to "ssh"
#
# == Author
#   Steeve McCauley
#
# == Copyright
#   Copyright (c) 2009 Steeve McCauley. Licensed under the GPL
#
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# $Id$

require 'optparse' 
require 'rdoc/usage'
require 'ostruct'
require 'date'
require 'socket'

require 'xmlsimple'

require 'rubac_db'
require 'szmsg'

#
# rsync version must be at least 2.5.6 for --link-dest option
#

class Config_rubac
	#
	# configuration template hash
	#
	def initialize
		@def_config = {
			'globals' => {
				'version' => {
					'major' => '0',
					'minor' => '5',
					'revision' => "$Rev$"[6..-3]
				},
				'opts' => '--delete-excluded',
				'includes' => '/root,/etc',
				'excludes' => '*/.thumbnails/,*/.thunderbird/*/ImapMail/,*/.beagle/,*/.mozilla/firefox/*/Cache/,*/.gvfs/,*/.cache/,*/.ccache/,*/.dvdcss/,*/.macromedia/,*/.local/share/Trash/,*/.mcop/,*/.mozilla-*/,*/tmp/'
			},
			'clients' => {
				'localhost' => {
					'includes' => '',
					'excludes' => '',
					'opts' => ''
				},
			}
		}
		@config = {}
	end

	# load the xml config
	def load_xml(file, path="./")
		@xml_file = File.join(path, file)
		if File.exist?(file)
			@config = XmlSimple.xml_in(file, 'ForceArray' => false)
		else
			@config = @def_config.to_hash
		end
		puts "##### load_xml #{@xml_file}"
		pp @config
	end

	# save the xml config
	def save_xml
		out = XmlSimple.xml_out(@config, { 'RootName' => 'rubac_config', 'NoAttr' => true, 'AttrPrefix' => true } )
		xml="<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>\n" + out

		file = File.new(@xml_file, "w")
		file << xml
		file.close
	end

	def add_client(host, includes, excludes, opts)
		client= {
			"#{host}" => {
				'includes' => includes,
				'excludes' => excludes,
				'opts' => opts
			}
		}
		@config['clients'].merge!(client)
	end

	def get_config
		@config
	end

	def get_global_conifig
		@config['globals']
	end

	def get_host_config(host)
		if not @config['clients'].has_key?(host)
			add_client(host, "", "", "")
		end
		@config['clients']["#{host}"]
	end

	# overwrite includes for specified client
	def set_client_includes(host, inc)
		get_host_config(host)
		@config['clients']["#{host}"]['includes'] = inc
	end

	# overwrite excludes for specified client
	def set_client_excludes(host, exc)
		get_host_config(host)
		@config['clients']["#{host}"]['excludes'] = exc 
	end

	# overwrite opts for specified client
	def set_client_opts(host, opts)
		get_host_config(host)
		@config['clients']["#{host}"]['opts'] = opts
	end

	# append (or set) the specified item for the specified client
	def append_client_key(host, item, key)
		get_host_config(host)
		# key can be a comma separated list, should convert to array
		# and compare all values of the with all values in keys below
		key.strip!
		if @config['clients']["#{host}"]["#{item}"].length > 0
			keys=@config['clients']["#{host}"]["#{item}"].split(",")
			keys.each do |i|
				if i == key 
					puts "Item #{item} already contains #{key}"
					return @config['clients']["#{host}"]["#{item}"]
				end
			end
			@config['clients']["#{host}"]["#{item}"] << ","
		end
		@config['clients']["#{host}"]["#{item}"] << key 
	end

	# append (or set) includes for specified client
	def append_client_includes(host, inc)
		append_client_key(host, "includes", inc)
	end

	# append (or set) excludes for specified client
	def append_client_excludes(host, exc)
		append_client_key(host, "excludes", exc)
	end

	# append (or set) opts for specified client
	def append_client_opts(host, opts)
		append_client_key(host, "opts", opts)
	end
end

class Rubac
	include Szmsg

	VERSION = '0.0.1'

	attr_reader :options

	def initialize(arguments, stdin)
		@arguments = arguments
		@stdin = stdin
		@revision = "$Rev$"[6..-3]
			      
		# Set defaults
		@options = OpenStruct.new
		@options.global = false
		@options.profile = "default"
		@options.dbname = nil
		
		begin
			@options.client = Socket.gethostname
		rescue
			@options.client = "localhost"
		end

		# 
		# If /etc/rubac is writable use it as default, otherwise use
		# ~/.rubac/ (does this work for windoze?)
		#
		if ENV['RUBAC_DATADIR']
			@options.data_dir = ENV['RUBAC_DATADIR']
		else
			if File.writable?("/etc/rubac")
				@options.data_dir = "/etc/rubac"
			else
				@options.data_dir = File.expand_path("~") + "/.rubac"
			end
			ENV['RUBAC_DATADIR'] = @options.data_dir

			info "Data directory is #{@options.data_dir}"
		end

		begin
			FileUtils.mkdir(@options.data_dir) if not File.exist?(@options.data_dir)
		rescue
			puts "Failed to create data directory #{@options.data_dir}"
			exit false
		end

		@options.verbose = false
		@options.quiet = false
		@options.include = nil
		@options.exclude = nil
		@options.opts = nil
		@options.run = false
		@options.cmd = nil
		@options.dry_run = false

		#
		# TODO - add additional defaults end
		#
	end

	# Parse options, check arguments, then process the command
	def burp
        
		if arguments_valid? && parsed_options?

			puts "Start at #{DateTime.now}\n\n" if @options.verbose

			output_options if @options.verbose # [Optional]

			process_arguments            
			process_command

			#puts "\nFinished at #{DateTime.now}" if @options.verbose
		else
			usage_command
		end
	end

	protected

	def set_command(c)
		if @options.cmd == nil
			@options.cmd="#{c}_command"
		else
			warn "Command is already set to #{@options.cmd}, ignoring #{c} command"
		end
	end

	def parsed_options?

		# Specify options
		opts = OptionParser.new 
		opts.on('-V', '--verbose', "Run verbosely")    { @options.verbose = true }  
		opts.on('-q', '--quiet',   "Run quietly")      { @options.quiet = true }

		opts.on('-cHOST', '--client HOST', "Backup Client hostname") do |host|
			@options.client = host
		end

		opts.on('-DPATH', '--data_dir PATH', "Database directory") do |dir|
			@options.data_dir = dir
		end

		opts.on('-iPATH', '--include PATH', "Add include path") do |inc|
			if @options.include
				@options.include = @options.include + ",#{inc}"
			else
				@options.include = inc
			end
		end

		opts.on('-xPATH', '--exclude PATH', "Add exclude path") do |exc|
			if @options.exclude
				@options.exclude = @options.exclude + ",#{exc}"
			else
				@options.exclude = exc
			end
		end

		opts.on('-PNAME', '--profile NAME', "Apply opts to specified profile") do |profile|
			@options.profile = profile
		end
		# TO DO - add additional options

		opts.on('-n', '--dry-run', "Perform a trial run of the backup") do
			@options.dry_run = true
		end
		opts.on('-h', '--help',    "Print help") do   #   { output_help }
			set_command("help")
		end
		opts.on('-r', '--run', "Run the backup") do
			set_command("run")
		end
		opts.on('-t', '--list', "List the backup options") do
			set_command("list")
		end
		opts.on('-H', '--history', "Backup history") do
			set_command("history")
		end
		opts.on('-v', '--version', "Print version") do
			set_command("version")
		end

		opts.parse!(@arguments) rescue return false

		process_options
		true      
	end

	# Performs post-parse processing on options
	def process_options
		@options.verbose = false if @options.quiet
		@options.dbname = @options.profile + ".xml"
	end

	def output_options
		puts "Options:\n"
      
		@options.marshal_dump.each do |name, val|        
			puts "  #{name} = #{val}"
		end
	end

	# True if required arguments were provided
	def arguments_valid?
		# TO DO - implement your real logic here
		#puts "arguments =  #{@arguments.length} \n"
		true if @arguments.length >= 1 
	end

	# Setup the arguments
	def process_arguments
		# TO DO - place in local vars, etc
	end
    
	def help_command 
		version_command
		RDoc::usage() #exits app
	end
    
	def usage_command
		RDoc::usage('usage') # gets usage from comments above
	end
    
	def run_command
		info "run command"
	end

	def list_command
		info "list command"
	end

	def history_command
		info "history command"
	end

	def version_command
		puts "#{File.basename(__FILE__, ".rb")} version #{VERSION}"
	end
    
	def process_command

		cfg = Config_rubac.new
		cfg.load_xml(@options.dbname, @options.data_dir)

		if @options.global
		else
			if @options.include
				cfg.append_client_includes(@options.client, @options.include)
			end
			if @options.exclude
				cfg.append_client_excludes(@options.client, @options.exclude)
			end
			if @options.opts
				cfg.append_client_opts(@options.client, @options.opts)
			end
		end

		#cfg.append_client_includes("linguini", "/data/osd")
		#cfg.append_client_excludes("linguini", "/data/osd/Etienne")
		#cfg.append_client_opts("linguini", "--delete-excluded")

		puts "##### #{@options.cmd} #####"
		if @options.cmd
			eval @options.cmd
		else
			# DEST is the backup directory
			# HOST is the client (localhost or `hostname -s` is considered local)
			# PROFILE is the name of the profile
			#
			# if exists /DEST/HOST/PROFILE/rubac.4 move it to /DEST/HOST/PROFILE/rubac.5
			# if exists /DEST/HOST/PROFILE/rubac.3 move it to /DEST/HOST/PROFILE/rubac.4
			# if exists /DEST/HOST/PROFILE/rubac.2 move it to /DEST/HOST/PROFILE/rubac.3
			# if exists /DEST/HOST/PROFILE/rubac.1 move it to /DEST/HOST/PROFILE/rubac.2
			# if exists /DEST/HOST/PROFILE/rubac.0 move it to /DEST/HOST/PROFILE/rubac.1
			# backup to /DEST/HOST/PROFILE/rubac.0
			#a=[]
			#a=(1..5).to_a.reverse
			#a.each do |y|
			#	x = y-1
			#	puts "mv /DEST/HOST/PROFILE/rubac.#{x} /DEST/HOST/PROFILE/rubac.#{y}"
			#end
		end

		cfg.save_xml

	end

	def process_standard_input
		input = @stdin.read      
		# TO DO - process input

		# [Optional]
		# @stdin.each do |line| 
		#  # TO DO - process each line
		# end
	end
end

rubac = Rubac.new(ARGV, STDIN)
rubac.burp

p Dir.glob("*")

