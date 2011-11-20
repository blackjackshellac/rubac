#!/usr/bin/env ruby
#
# == Synopsis 
#   A ruby backup front-end powered by rsync that can save
#   multiple backup profiles between uses.
#
# == Usage 
#   rubac [options]
#
#   For help use: rubac -h
#
# == Options
#   -g, --global            Apply includes, excludes, options etc., to global settings 
#   -p, --profile [NAME]    Name of backup profile (default is rubac), list profiles without NAME
#   -D, --datadir PATH      Configuration directory (if root /etc/rubac otherwise ~/.rubac)
#
#   -c, --client HOST       Client to backup (default is localhost), can specify multiple clients
#   -a, --address HOST      Set the client host address (default is the client name)
#   -i, --include PATH      Include path, comma separate multiple paths
#   -x, --exclude PATH      Exclude path, comma separate multiple paths
#   -o, --opts OPTS         Extra rsync options
#       --delete            Delete any specified includes, excludes, opts
#       --delete [client]   Delete the specified client configuration (does not purge the backups)
#   -d, --dest DEST         Local destination path (eg., /mnt/backup)
#
#   -L, --logdir PATH       Directory for logging (root default is /var/log/rubac, otherwise TMP/rubac)
#       --log [NAME]        TODO Name of log file, (default is rubac.%Y-%m-%d.log)  - allow date/time formats 
#   -m, --mail EMAIL        Notification email, comma separated list
#       --smtp SERVER       IP Address of smtp server (default is localhost)
#   -y, --syslog            TODO Use syslog for logging [??] [probably not since we have privlog]
#
#   -l, --list [compact]    List the includes, excludes, etc., for the named profile
#   -u, --update            Perform update backup, no incremental backups
#   -I, --incremental NUM   Number of incremental backups (default is 5)
#   -r, --run               Run specified profile
#   -s, --snapshot NAME     Created a snapshot based on most recent backup
#   -n, --dry-run           Perform a trial run of the backup
#   -z, --compress          Compress the file data during backup
#
#   -H, --history [INDEX]   Backup history, or specify index to see backup details
#   -P, --prune             Delete the selected backup or snapshot (TODO)
#       --select [NAME]     TODO Select a backup for pruning or restoring (special names: newest, oldest)
#   -R, --restore [PATH]    Restore path, choose the backup with --select
#       --restore-to PATH   Restore to the given host:path (default is client:/TMP)
#       --restore-from FILE Restore file list from the given file (comma or new line delimited)
#   -S, --search PATTERN    Search for the given glob in the backup history, optionally restore files found using restore without a path
#
#   -h, --help              Displays help
#       --examples          Displays examples
#   -v, --version           Display the version
#   -q, --quiet             Output as little as possible, overrides verbose
#   -V, --verbose           Verbose output
#
# == Examples
#
# Setup and use a default backup
#
#   rubac -c esme -g -o "--acls --xattrs"
#   rubac -c esme -i "/home/steeve,/home/lissa,/home/etienne" -x "*/.gvfs/"
#   rubac -c esme -x "*/.thumbnails/,*/.thunderbird/*/ImapMail/,*/.beagle/"
#   rubac -c esme -m backupadmin@mail.host
#   rubac -c esme -l /var/log/rubac
#   ...
#   rubac -c esme --run
#   rubac -c esme --update
#
# List then show history of client esme
#   rubac -c esme --list compact
#   rubac -c esme --history
#
# Search for all files named .bashrc
#   rubac -c esme --search '.bashrc$'
#
# Restore all files named file.dat to the local tmp directory instead of esme:/tmp
#   rubac -c esme --restore-to=localhost:/tmp --select rubac.2010-01-29_10-40-29 --restore file.dat
#
# Restore the directory /home/steeve/Desktop in place to esme:/
#   rubac -c esme --restore-to=esme:/ --restore /home/steeve/Desktop/$
#
# Search for all ogg vorbis files and restore them to /tmp
#   rubac -c esme --restore --restore-to=/tmp --search 'caravan.palace'
#
# == Environment Variables
#
#   RUBAC_DATADIR - set the database directory
#   RUBAC_PROFILE - set the backup profile to use
#   RUBAC_CLIENT  - set the client to use
#   RUBAC_SSHOPTS - set the ssh opts (defaults to -a)
#   RUBAC_RSYNC   - set the rsync command path
#   RSYNC_RSH     - ssh command string, defaults to "ssh" here
#
# == Author
#   Steeve McCauley steeve@oneguycoding.com
#
# == Copyright
#
#   Copyright (c) 2011 Steeve McCauley. Licensed under the GPL
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

require 'optparse' 
require 'net/smtp'
require 'ostruct'
#require 'date'
#require 'socket'
#require 'etc'
#require 'open3'
require 'tmpdir'
require 'yaml'
require 'logger'

# add to front of $LOAD_PATH if this file's dir isn't already there
rreqdir=File.expand_path(File.dirname(__FILE__))
$:.unshift(rreqdir) unless $:.include?(rreqdir)

require 'rubac/config'	# rubac config
require 'rubac/helper'  # rubac help from headers
require 'rubac/stack'   # simple push/pop stack with a limited number of entries
require 'rubac/msgLogger' # logger class that can cache recent messages

$msg = Rubac::MsgLogger.new("console")

#$debug = true

CONFIG_KEY_VER="version"
CONFIG_KEY_VER_MAJ="major"
CONFIG_KEY_VER_MIN="minor"
CONFIG_KEY_VER_REV="revision"

CONFIG_KEY_GLOBALS="globals"
CONFIG_KEY_INC="includes"
CONFIG_KEY_EXC="excludes"
CONFIG_KEY_OPT="opts"
CONFIG_KEY_DEST="dest"
CONFIG_KEY_NINC="ninc"
CONFIG_KEY_LOGDIR="logdir"
CONFIG_KEY_LOGNAME="logname"
CONFIG_KEY_EMAIL="email"
CONFIG_KEY_SMTP="smtp"

UPDATE_CMD_ADD="add"
UPDATE_CMD_DEL="delete"

$help=Rubac::HeaderHelp.new(__FILE__)
#puts $help.list
#$help.print([ "Synopsis", "Usage", "Examples", "Environment Variables" ])

class Email
	attr :server, true

	def initialize(server="localhost")
		@server=server
		@to = []
		@from = {}
		@attach = nil
	end

	def address_email(addr, name=nil)
		return if not addr
		addr.strip!
		name.strip! if name
		eaddr = { :name => name, :addr => addr }
		eaddr.to_hash
	end

	def to(addr, name=nil)
		@to << address_email(addr, name)
	end

	def from(addr, name=nil)
		@from = address_email(addr, name)
	end

	def send(subject, body, server=nil)
		@server = server if server != nil

		tstr = ""
		@to.each do |a|
			tstr << "#{a[:name]} " if a[:name]
			tstr << "<#{a[:addr]}>, "
		end
		fstr = ""
		fstr << "#{@from[:name]} " if @from[:name]
		fstr << "<#{@from[:addr]}> "

		sstr = "#{subject}"

		msg = <<END_OF_MESSAGE
From: #{fstr}
To: #{tstr}
Subject: #{sstr}

\n#{body}
END_OF_MESSAGE
 
		@to.each do |a|
			#puts "Sending message to #{a[:addr]}\n" + msg
			begin
				Net::SMTP.start(@server) do |smtp|
					smtp.send_message msg, @from[:addr], a[:addr]
				end
			rescue Errno::ECONNREFUSED
				puts "Connection to smtp server #{@server} refused"
			rescue
				puts "Failed to send msg to smtp server #{@server}"
			end
		end
	end
end

module Rubac 
# Rubac
#
# main rubac class
#
class Rubac

	attr_reader :options

	def initialize(arguments, stdin)

		@rsync = ENV['RUBAC_RSYNC'] ? ENV['RUBAC_RSYNC'] : "rsync"

		@includes = ""
		@excludes = ""
		# rsync -a --relative --delete --delete-excluded --link-dest=/home/rubac/linguini/default/rubac.1 /home/etienne /home/rubac/linguini/default/rubac.0
		@sshopts = {}
		if ENV['RUBAC_SSHOPTS']
			@sshopts["global"] = ENV['RUBAC_SSHOPTS']
		else
			@sshopts["global"] = "-a -v -v"
			@sshopts["restore"] = "-a -r -v -v"
		end
		# don't --delete on update command, add this on run only
		#@sshopts["global"] << " --relative --delete-excluded --ignore-errors --one-file-system"
		#@sshopts["restore"] << " --relative --ignore-errors --one-file-system"
		@sshopts["global"] << " --relative --delete-excluded --ignore-errors --one-file-system"
		@sshopts["restore"] << " --relative --one-file-system"
		#@sshopts["global"] << " --acls"
		#@sshopts["global"] << " --xattrs"

		# use the value set in the environment, if set
		@rsync_rsh = ENV['RSYNC_RSH'] ? ENV['RSYNC_RSH'] : "-e ssh"

		@arguments = arguments
		@stdin = stdin
		@revision = "$Rev$"[6..-3]
			      
		# Set defaults
		@options = OpenStruct.new
		@options.global = false
		@options.dbname = nil
		@options.ninc = nil	# means 5 incrementals, 1-5 with main backup 0
		
		if ENV['RUBAC_PROFILE'] and ENV['RUBAC_PROFILE'].length > 0
			@options.profile = File.basename(ENV['RUBAC_PROFILE'], ".yaml")
		else
			@options.profile = "rubac"
		end

		# hn = Socket.gethostname
		# "lingini.home"
		# hna = Socket.gethostbyname(hn)
		# ["linguini.home", [], 2, "\300\250\001o"]
		#begin
		#	@options.client = Socket.gethostname
		#rescue
		#	@options.client = "localhost"
		#end
		if ENV['RUBAC_CLIENT'] and ENV['RUBAC_CLIENT'].length > 0
			clients = ENV['RUBAC_CLIENT']
			@options.client = clients.split(",")
		else
			@options.client = [ ]
		end
		@options.all = false

		# 
		# If /etc/rubac is writable use it as default, otherwise use
		# ~/.rubac/ (does this work for windoze?)
		#
		if ENV['RUBAC_DATADIR']
			@options.datadir = ENV['RUBAC_DATADIR']
		else
			system_dir = "/etc/rubac"
			use_local = true
			begin
				Dir.mkdir(system_dir)
				use_local = false
			rescue Errno::EACCES
				use_local = true
			rescue Errno::EEXIST
				use_local = false
			end

			if use_local == false and File.writable?(system_dir)
				@options.datadir = system_dir
			else
				@options.datadir = File.expand_path("~") + "/.rubac"
			end
			ENV['RUBAC_DATADIR'] = @options.datadir
		end

		begin
			FileUtils.mkdir(@options.datadir) if not File.exist?(@options.datadir)
		rescue
			$msg.die "Failed to create data directory #{@options.datadir}"
		end

		@options.verbose = false
		@options.quiet = false
		@options.update_cmd = UPDATE_CMD_ADD
		@options.delete_client = []
		@options.includes = nil
		@options.excludes = nil
		@options.dest = nil
		@options.opts = nil
		@options.snapshot = nil
		@options.listkey = nil
		@options.run = false
		@options.update = false
		@options.cmd = nil
		@options.dry_run = false
		@options.compress = false
		@options.email = nil
		@options.smtp = nil
		@options.hist_index = nil
		@options.select = nil
		@options.address = nil
		@options.search = []

	  @options.tmp = ENV['TMP'] ? ENV['TMP'] : Dir::tmpdir

		@options.restore = []
		@options.search_restore = false
		@options.restore_to = nil
		@options.restore_from = nil

		# use default log (constructed after processing arguments)
		@options.logdir = nil
		@options.logname = nil
		@options.logfmt = "%Y-%m-%d"

		#
		# TODO - add additional defaults end
		#
	end

	# ensure that rsync is at least 2.5.6
	def rsync_check_version
		# rsync version must be at least 2.5.6 for --link-dest option
		rsync_version = `#{@rsync} --version`
		if $?.exitstatus != 0
			$msg.die "running #{@rsync} --version"
		end
		rsync_version = rsync_version[/^rsync\s+version\W+\d+\.\d+\.\d+/]
		if rsync_version == nil
			$msg.die "could not determine rsync version"
		end
		rsync_version = rsync_version[/\d+\.\d+\.\d/]
		rva = rsync_version.split(/\./)
		rvi = rva[0].to_i * 100 + rva[1].to_i * 10 + rva[2].to_i
		if rvi < 256
			$msg.die "rsync version is too old, require at least rsync version 2.5.6"
		end
	end

	# Parse options, check arguments, then process the command
	def run
 
	  $ret=0
	  
		rsync_check_version

		if arguments_valid? && parsed_options?

			t0 = Time.now
			$msg.info "Start at #{t0.to_s}" if @options.verbose

			output_options if @options.verbose # [Optional]

			process_arguments            
			process_command

			t1 = Time.now
			$msg.info "Finished at #{t1.to_s}" if @options.verbose
			t1 = t1-t0
			$msg.info "Runtime #{t1.to_f}"
		else
			usage_command
		end
		
		exit $ret
		
	end

	protected

	def set_command(c)
		if @options.cmd == nil
			@options.cmd="#{c}_command"
		elsif @options.cmd[/^#{c}_command$/]
			$msg.warn "Command \"#{c}\" already set"
		else
			$msg.warn "Command is already set to #{@options.cmd}, ignoring #{c} command"
		end
	end

	def parse_option_list(list, opt, delim=",")
		# strip whitespace
		opt.strip!
		opts = []
		opts = list.split(delim) if list
		opts << opt 
		opts.join(delim)
	end

	def parsed_options?

		# Specify options
		opts = OptionParser.new 
		opts.on('-V', '--verbose', "Run verbosely")    { @options.verbose = true }  
		opts.on('-q', '--quiet',   "Run quietly")      { @options.quiet = true }

		opts.on('-g', '--global', "Apply options to the global settings") { @options.global = true }

		opts.on('--delete [CLIENT]', "Delete any specified includes, excludes, opts ... or the specified client") do |cli|
			@options.update_cmd = UPDATE_CMD_DEL
			if cli
				$msg.info "Setup #{cli} for deletion"
				@options.delete_client << cli if cli
			end
		end

		opts.on('-LPATH', '--logdir PATH', "Set the log directory") do |dir|
			@options.logdir = dir
		end
		
		opts.on('--log PATH', "Set the log file name") do |name|
			@options.log = File.basename(name)
		end

		opts.on('-cHOST', '--client HOST', "Backup Client hostname") do |host|
			host.strip!
			@options.client << host
			@options.client.uniq!
		end

		opts.on('-aHOST', '--address HOST', "Address of the specified client") do |address|
			address.strip!
			@options.address = address
		end

		opts.on('-DPATH', '--datadir PATH', "Database directory") do |dir|
			dir.strip!
			@options.datadir = dir
		end

		opts.on('-iPATH', '--include PATH', "Add include path") do |inc|
			delim=","
			@options.includes = parse_option_list(@options.includes, inc, delim) 
			# remove trailing pathslash, if any
			#inc = File.join(File.dirname(inc), File.basename(inc))
			opts = @options.includes.split(delim)
			opts.each do |o|
				next if o == '/'
				o.sub!(/\/$/, "")
			end
			@options.includes = opts.join(delim)
		end

		opts.on('-xPATH', '--exclude PATH', "Add exclude path") do |exc|
			@options.excludes = parse_option_list(@options.excludes, exc, ",")
		end

		opts.on('-oOPTS', '--opts OPTS', "Add ssh options") do |opt|
			@options.opts = parse_option_list(@options.opts, opt, " ")
		end

		opts.on('-dPATH', '--dest PATH', "Set backup destination") do |dest|
			dest.strip!
			@options.dest = dest
		end

		opts.on('-mLIST', '--mail LIST', "Email notification list") do |email|
			@options.email = email
		end

		opts.on('--smtp SERVER', "SMTP server address") do |server|
			@options.smtp = server
		end

		opts.on('-I', '--incremental N', "Set the number of incremental backups") do |ninc|
			ninc = ninc.to_i
			if ninc < 0
				$msg.err "number of incrementals must be greater than or equal to 0, ignoring #{ninc}"
			else
				@options.ninc = ninc
			end
		end

		opts.on('-p', '--profile [NAME]', "Apply opts to specified profile") do |profile|
			if not profile
				$msg.info "\nListing profiles in #{@options.datadir}\n\n"
				cmd="ls -l #{@options.datadir}/*.yaml"
				exec(cmd)
			end
			@options.profile = File.basename(profile, ".yaml")
		end
		# TO DO - add additional options

		opts.on('-n', '--dry-run', "Perform a trial run of the backup") do
			@options.dry_run = true
		end

		opts.on('-z', '--compress', "Compress the file data during backup") do
			@options.compress = true
		end

		opts.on('-h', '--help',    "Print help") do   #   { output_help }
			set_command("help")
			#puts opts.to_s
		end

		opts.on('--examples', "Display examples") do
			set_command("examples")
		end

		opts.on('-u', '--update', "Perform an update backup ignoring incrementals") do
			@options.update = true
			set_command("run")
		end

		opts.on('-r', '--run', "Run the backup") do
			set_command("run")
		end

		opts.on('-sNAME', '--snapshot NAME', "Perform a snapshot backup") do |name|
			@options.snapshot = File.basename(name)
			set_command("snapshot")
		end

		opts.on('-l [KEYWORD]', '--list [KEYWORD]', "List the backup options") do |keyword|
			set_command("list")
			@options.listkey = keyword
		end

		opts.on('-H', '--history [INDEX]', "Backup history") do |index|
			set_command("history")
			@options.hist_index = index.to_i if index != nil
		end

		opts.on('-P', '--prune', "Delete the selected backup or snapshot") do
			set_command("prune")
		end

		opts.on('--select NAME', "Select a backup for pruning or restoring") do |name|
			@options.select = name.to_s
		end

		opts.on('-S', '--search glob', "Search backup history") do |glob|
			set_command("search")
			@options.search << glob
		end

		opts.on('R', '--restore [PATH]', "Restore file or directory, choose backup with --select, default is most recent") do |path|
			if path
				set_command("restore")
				@options.restore << path
			else
				$msg.info "Search results will be restored"
				@options.search_restore = true
			end
		end

		opts.on('--restore-to PATH', "Restore to the given base path (default is client:TMP)") do |path|
			@options.restore_to = path
		end

		opts.on('--restore-from FILE', "Restore file list from the given file (comma or new line delimited)") do |file|
			set_command("restore")
			$msg.die "--restore-from #{file} not found" if not File.exist?(file)
			@options.restore_from = file
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
		@options.dbname = @options.profile + ".yaml"
	end

	def output_options
		$msg.info "Options:\n"
      
		@options.marshal_dump.each do |name, val|        
			$msg.info "  #{name} = #{val}"
		end
	end

	# True if required arguments were provided
	def arguments_valid?
		# TO DO - implement your real logic here
		#puts "arguments =  #{@arguments.length} \n"
		true if @arguments.length >= 1 
	end

	def process_arguments_clients
		return if @options.client.length > 0
		@options.client = @config.get_clients.keys
		@options.all = true
		$msg.debug "clients = #{@options.client.join(", ")}"
	end

	def check_backup_destination(dest)
		if not File.exist?(File.join(dest, "rubac.init"))
			$msg.die "destination #{dest} not initialized, mount or re-initialize with --dest #{dest}"
			false
		end
		# TODO validate backup destination?
		true
	end

	def initialize_backup_destination(dest)
		begin
			FileUtils.mkdir_p(dest)
		rescue
			$msg.die "creating backup destination #{dest}"
		end

		begin
		fd=File.new(File.join(dest, "rubac.init"), File::CREAT|File::RDWR|File::EXCL, 0600)
		rescue Errno::EACCES
			$msg.die "access denied, initializing destination #{dest}"
		rescue Errno::EEXIST
			$msg.warn "backup destination #{dest} is already initialized"
			return true
		rescue
			$msg.die "initializing destination #{dest}"
		end
		fd.close
		true
	end

	def prompt_string(msg)
		printf "%s ", msg
		reply = gets.chomp
		return reply.length > 0 ? reply : false
	end

	def prompt_char(msg, chrs)
		printf "%s [%s] ", msg, chrs
		reply = gets.chomp[0].chr
		reply = chrs[/#{reply}/]
		return reply
	end

	# Setup the arguments
	def process_arguments
		# TO DO - place in local vars, etc
		@config = Config.new
		if not @config.load(@options.dbname, @options.datadir)
			ans = prompt_char("Do you want to create a new profile?", "yn")
			$msg.die "Aborting" if ans != "y"
			ans = prompt_string("Backup destination directory:")
			if ans
				if not File.exist?(ans)
					$msg.warn "Destination directory #{ans} not found"
				elsif not File.lstat(ans).directory?
					$msg.die "Destination #{ans} is not a directory"
				end
				@options.dest = ans
			end
		end

		# setup logging immediately after loading the configuration
		if @options.logdir == nil
			logdir = @config.get_global_key_value("logdir")
			if logdir.length == 0
				if Process.uid == 0
					logdir = "/var/log/rubac"
				else
					logdir = "#{@options.tmp}/rubac"
				end
			end
		else
			logdir = @options.logdir
		end

		if @options.logname == nil
			logname = @config.get_global_key_value("logname")
			if logname.length == 0
				logname = "#{@options.profile}.#{date_time_str(@options.logfmt)}.log"
			end
		else
			logname = @options.logname
		end

		@config.set_global_key_value("logname", @options.logname) if @options.logname
		@config.set_global_key_value("logdir", @options.logdir) if @options.logdir
		@config.set_global_key_value("email", @options.email) if @options.email
		@config.set_global_key_value("smtp", @options.smtp) if @options.smtp

		# setup logging and notification
		$msg.debug "log=#{logdir}/#{logname}"
		$msg.privlog(logname, logdir, 0600)
		# def notify(to_addr, to_name, from_addr, from_name, server='localhost')
		@options.email = @config.get_global_key_value("email")
		if @options.email.length > 0
			@options.smtp = @config.get_global_key_value("smtp")
			@options.smtp = nil if @options.smtp.length == 0
			from = "#{Etc.getlogin}@#{Socket.gethostname}"
			$msg.info "Setup notify email to #{@options.email} from #{from} using server=#{@options.smtp}"
			$msg.notify(@options.email, from, @options.smtp)
		end

		version_command

		if @options.dest
			initialize_backup_destination(@options.dest)
			@config.set_global_key_value("dest", @options.dest)
		end

		process_arguments_clients

		if @options.global
			@config.global_update(@options.update_cmd, "includes", @options.includes, ",")
			@config.global_update(@options.update_cmd, "excludes", @options.excludes, ",")
			@config.global_update(@options.update_cmd, "opts", @options.opts, " ")
			@config.global_update(@options.update_cmd, "ninc", @options.ninc)
			@config.global_update(@options.update_cmd, "compress", @options.compress)
		else
			@options.client.each do |client|
				#@config.client_updates(client, @options.update_cmd, @options.includes, @options.excludes, @options.opts)
				@config.client_update(client, @options.update_cmd, "includes", @options.includes, ",")
				@config.client_update(client, @options.update_cmd, "excludes", @options.excludes, ",")
				@config.client_update(client, @options.update_cmd, "opts", @options.opts, " ")
				@config.client_update(client, @options.update_cmd, "address", @options.address)
				@config.client_update(client, @options.update_cmd, "ninc", @options.ninc)
				@config.client_update(client, @options.update_cmd, "compress", @options.compress)
			end
		end

		if @options.delete_client.length > 0
			@options.delete_client.each do |cli|
				$msg.info "Deleting client #{cli}"
				@config.del_client(cli)
			end
		end

		@config.save(@options.dbname, @options.datadir)
	end
    
	def print_command(suffix="")
		$msg.info "##### #{@options.cmd.sub(/_command/, '')} for #{@client} #{suffix} #####"
	end

	def help_command 
		# RDoc::usage doesn't work in 1.9.x
		#RDoc::usage('Synopsis', 'Usage', 'Options') #exits app
		$help.print([ "Synopsis", "Usage", "Options" ])
	end
    
	def usage_command
		#RDoc::usage('Synopsis', 'Usage', 'Options') # gets usage from comments above
		$help.print([ "Synopsis", "Usage", "Examples", "Environment Variables" ])
	end

	def examples_command
		#RDoc::usage('Examples')
		$help.print("Examples")
	end
 
	def run_command_prep_linkdest(host, pdest)
		return nil if @ninc == 0

		# setup flags for delete
		#rm_flags = { :force => true } # , :verbose => true }
		#if @options.dry_run 
		#	rm_flags.merge!( :noop => true )
		#end

		expire = ""

		(1..@ninc).to_a.reverse.each do |m|
			n = m - 1
			# Example,
			#   n==4, ndest is rubac.4
			#   m==5, mdest is rubac.5

			nname = @config.get_client_incrementals(host, n)
			mname = @config.get_client_incrementals(host, m)

			$msg.debug "n=#{n} nname=#{nname} m=#{m} mname=#{mname}"

			next if nname.length == 0

			ndest = File.join(pdest, nname)
			mdest = File.join(pdest, mname)

			# Someone has deleted an incremental backup
			if not File.exist?(ndest)
				#@config.set_client_incremental(host, m, nname)
				$msg.err "incremental backup #{nname} not found"
				@config.set_client_incremental(host, m, "")
				@config.set_client_incremental(host, n, "")
				next
			end

			if m == @ninc and mname.length > 0
				if File.exist?(mdest)
					#$msg.info("deleting expired incremental: #{mdest}")
					#FileUtils.rm_r(mdest, rm_flags)
					expire = mdest
				end
			end
			if File.exist?(ndest)
				@config.set_client_incremental(host, m, nname)
			end
		end
		# return the entry to delete
		expire
	end

	def run_command_fill(droot, path, log)
		bdir = Dir.new(path)
		bdir.each { |d|
			next if d == "." or d == ".."
			p = File.join(path, d)
			q = p.sub(/^#{droot}/, "")
			if File.lstat(p).directory?
				q << "/"
				log << "#{q}"
				#puts ":d:#{q}:d:"
				run_command_fill(droot, p, log)
			end
			log << "#{q}"
			#puts ":f:#{q}:f:"
		}
	end

	# return value is 0 for okay, > 0 otherwise
	def run_command_rsync(host, bdest, ldest)

		logf = File.join(bdest, "rubac.log.yaml")
		if File.exist?(logf)
			fill = false
			log = File.open(logf) { |yf| YAML::load(yf) }
			$msg.log "Log found: loaded #{logf} with #{log.length}"
		else
			fill = true
			log = Array.new
		end

		return 1 if @includes.length == 0

		src = ""
		@includes.split(",").each do |inc|
			inc.strip!
			inc = "#{@address}:#{inc}" if @address != "localhost" and @address != "127.0.0.1"
			src << "#{inc} "
		end
		src.rstrip!

		cmd =  "rsync -r #{@sshopts["global"]} #{@sshopts["#{host}"]}"
		cmd << " --delete" if not @options.update
		cmd << " --link-dest=#{ldest}" if ldest

		# create files-from temporary file
		#incl = File.join(@options.tmp, File.basename(bdest) + ".#{host}.incl")
		#incf = File.open( incl, "w" )
		#@includes.split(",").each do |inc|
		#	inc.strip!
		#	inc = File.join(File.dirname(inc), File.basename(inc)) if inc[/\/$/]
		#	#inc = " #{@address}:#{inc}" if @address != "localhost" and @address != "127.0.0.1"
		#	incf.puts( inc )
		#end
		#incf.close

		# write the excludes to a file and use --exclude-from 
		excl = nil
		if @excludes.length > 0
			excl = File.join(@options.tmp, File.basename(bdest) + ".#{host}.excl")
			exclf = File.open( excl, "w" )
			#exclf.puts("/")
			@excludes.split(",").each do |x|
				exclf.puts( x )
			end
			exclf.close
			cmd << " --exclude-from=\"#{excl}\""
		end

		# with files-from we use "/" as the src (or host:/ for remote)
		#src = "/"
		#src = " #{@address}:#{src}" if @address != "localhost" and @address != "127.0.0.1"
		# cmd << " --files-from=\"#{incl}\""

		cmd << " #{src}"
		cmd << " #{bdest}"

		#Open3.popen3(cmd) { |stdin,stdout,stderr|
		#}
		
		# create a stack to hold the last 10 lines of output
		estack = Rubac::Stack.new(10)

		$msg.log cmd
		$msg.print "Backup #{@includes}\n"
		$msg.print "\t--delete\n" if not @options.update
		$msg.print "\t--link-dest    #{ldest}\n" if ldest
		#$msg.print "\t--files-from   #{incl}\n"
		$msg.print "\t--exclude-from #{excl}\n" if excl
		$msg.print "\t               #{src}\n"
		$msg.print "\t               #{bdest}\n"

		incs=@includes.split(",")
		# write stderr to stdout
		cmd << " 2>&1"
		p = IO.popen(cmd)
		while (line = p.gets)
			line.chop!

			estack.push(line)

			# sent 78708 bytes  received 38072683 bytes  1956481.59 bytes/sec
			if line =~ %r{(?:sent)(?:\s+)(\d+)(?:\s+bytes\s+received\s+)(\d+)(?:\s+bytes\s+)(\d+\.\d+)(?:\s+bytes\/sec)}
				$msg.print "\tsent #{$1} bytes, recv #{$2} bytes, rate #{$3} bytes/sec\n"
				$msg.log "$ #{line}"
				next
			end

			# total size is 77334376  speedup is 2.81
			if line =~ %r{(?:total size is\s+)(\d+)(?:\s+speedup is\s+)(\d+\.\d+)}
				$msg.print "\tsize #{$1}, speedup #{$2}\n"
				$msg.log "$ #{line}"
				next
			end

			if line[/\sis uptodate$/]
				line.sub!(/\sis uptodate$/, "")
				$msg.debug "uu:#{line}:uu"
				log << "/" + line
				$msg.print "#{line} is uptodate\n" if @options.verbose
				next
			end

			if line[/^\s*deleting\s+/]
			# if deleting, remove the file from 'log', if it exists
			# ^deleting home/rico/.thumbnails/normal/6bf9e300a41296740a5fdd89b98e1d93.png
				line.sub!(/^\s*deleting\s+/, "/")
				$msg.log "Deleting #{line}"
				$msg.print "Deleting #{line}\n" if @options.verbose
				log.delete(line)
			end

			inc = nil
			incs.each do |i|
				if line[/^#{i[1..-1]}/]
					inc = i
					line = "/" + line
					$msg.debug "//:#{line}://"
					break
				end
			end

			if inc and line[/^#{inc}.*/]
				$msg.log line
				log << line
				$msg.print "#{line}\n" if @options.verbose
			#elsif line[/^\[sender\] hiding directory\s/]
			#	$msg.log line
			else
				$msg.log "$ #{line}"
				$msg.print "#{line}\n" if @options.verbose
			end
		end
		# must close IO to get exitstatus into $?
		p.close
		ret = $?.exitstatus
		status = ret == 0 ? "Success" : "Fail"
		$msg.print "\t#{status} ret=#{ret}\n"
		if status == "Fail"
			$msg.err "command failed #{cmd}"
			$msg.info " >>>> command output <<<<<"
			estack.each do |line|
				$msg.info " >> #{line}"
			end
			$msg.info " >>>>"
		end

		#bdir = File.join(bdest, inc)
		#run_command_fill(bdest, bdir, log) if fill

		# remove duplicates
		log.uniq!

		$msg.log "Backup log length=#{log.length} to #{logf}"
		File.open( logf, "w" ) do |out|
			YAML.dump( log, out )
		end
		return ret
	end

	def date_time_str(fmt="%Y%m%d")
		Time.now.strftime(fmt)
	end

	def get_backup_dirname(name="rubac.", ext="")
		name + date_time_str("%Y%m%d") + ext
	end

	def get_client_dir(host, create=false, backup=nil, path=nil)
		dest=File.join(@dest, @options.profile, host)
		dest=File.join(dest, backup) if backup
		FileUtils.mkdir_p(dest) if create
		dest=File.join(dest, path) if path
		dest
	end

	def accept_signals(default=true)
		if default
			Signal.trap("TERM", "DEFAULT")
			Signal.trap("INT", "DEFAULT")
			Signal.trap("HUP", "DEFAULT")
		else
			Signal.trap("TERM", "trapSigTerm")
			Signal.trap("INT", "trapSigInt")
			Signal.trap("HUP", "trapSigHup")
		end
	end

	# backup to bdir with hardlink to ldir, if it exists
	def run_command
		print_command

		host = @client

		if @includes.length == 0
			$msg.err "nothing included in backup"
			return 1
		end

		ldir = bdir = ""
		if @options.snapshot
			bdir = "rubac.snapshot.#{@options.snapshot}"
			ldir = @select
			ldir = @config.get_client_incrementals(host, 0) if not ldir
		elsif @options.update
			bdir = @config.get_client_incrementals(host, 0)
			# TODO should I set ldir for update?
			# ldir = @config.get_client_incrementals(host, 1)
		else
			# if ninc == 0 do update (with delete?)
			if @ninc == 0
				bdir = @config.get_client_incrementals(host, 0)
			else
				bdir = get_backup_dirname
				ldir = @config.get_client_incrementals(host, 0)
			end
		end

		bdir = get_backup_dirname if bdir.length == 0
		ldir = "__none__" if ldir.length == 0

		pdest = get_client_dir(host, true)

		# if flock(LOCK_EX|LOCK_NB) == false puts "cannot get exclusive lock"
		# g=File.new("/tmp/junkol", File::CREAT|File::RDONLY, 0600)
		# g.flock(File::LOCK_EX|File::LOCK_NB)
		#
		rlock = File.join(pdest, "rubac.runlock")
		runlock = File.new(rlock, File::CREAT|File::RDONLY, 0644)
		if runlock.flock(File::LOCK_EX|File::LOCK_NB) == false
			$msg.err "cannot lock file #{rlock}"
			runlock.close
			return 1
		end

		bdest = File.join(pdest, bdir)
		ldest = File.join(pdest, ldir)
		$msg.debug "bdir=#{bdest} ldir=#{ldest}"

		expire = ""
		if @options.snapshot
			if not File.exist?(ldest)
				$msg.err "run one backup before doing a snapshot"
				return 1
			end
		elsif @options.update
			$msg.info "Running update on #{bdest}"
			ldest = nil if not File.exist?(ldest)
		else
			# move out incrementals
			expire = run_command_prep_linkdest(host, pdest) if ldir != "__none__"
			# if the link destination doesn't exist, set it to nil
			ldest = nil if not File.exist?(ldest)
		end

		# assert that bdest doesn't exist here?
		FileUtils.mkdir_p(bdest)

		# copy previous backup log to bdest, but only if it doesn't
		# already exist
		#blogf = File.join(bdest, "rubac.log.yaml")
		#if not File.exist?(blogf) and ldest
		#	llogf = File.join(ldest, "rubac.log.yaml")
		#	if File.exist?(llogf)
		#		FileUtils.copy(llogf, blogf, :verbose => true)
		#	end
		#end

		# log history files by include
		# include => "file, file, file, ..."
		#
		status = 0
		#inc = @includes.split(",")
		#inc.each do |i|
		#	# strip off any trailing path slashes
		#	ifp = File.join(File.dirname(i), File.basename(i))
		#	status = run_command_rsync(host, ifp, bdest, ldest)
		#	break if status > 0
		#end

		accept_signals(false)

		status = run_command_rsync(host, bdest, ldest)

		rm_flags = { :force => true , :verbose => true }
		rm_flags.merge!( :noop => true ) if @options.dry_run 
		if status == 0
			if expire and expire.length > 0 and File.exist?(expire)
				$msg.info("deleting expired incremental: #{expire}")
				FileUtils.rm_r(expire, rm_flags)
			end
			@config.set_client_incremental(host, 0, bdir) if not @options.snapshot
			@config.save(@options.dbname, @options.datadir) if not @options.dry_run
			FileUtils.rm_r(bdest, rm_flags) if @options.dry_run
		elsif not @options.update
			$msg.info("deleting incomplete backup")
			FileUtils.rm_r(bdest, rm_flags)
		end

		#if @options.dry_run and not @options.update
		#	$msg.info "--dry-run, removing backup #{bdest}"
		#	FileUtils.rm_r(bdest, :force => true , :verbose => true )
		#end

		runlock.flock(File::LOCK_UN)
		File.delete(rlock)

		accept_signals(true)

		if $signal_exit == true
			$msg.err("aborting on signal")
			return status
		end
		return status
	end

	#
	# Do a backup snapshot (not a real filesystem snapshot) by
	# backing up to the snapshot and linking to rubac.0
	#
	def snapshot_command
		print_command(@options.snapshot)
		run_command
	end

	def list_command_client_key(client, key, delim=",")
		if delim
			inc = @config.get_client_key_list(client, key, delim)
		else
			inc = @config.get_client_key_value(client, key)
			delim = " "
		end

		return if inc.length == 0

		if @options.listkey == "compact"
			$msg.printf "%10s=\'%s\'\n", key, inc
			return
		end

		inc = inc.split("#{delim}")
		$msg.printf "%10s=", key

		if inc.length > 1
		inc.each do |i|
			$msg.printf "\n\t%-12s", i
		end
		else
			$msg.printf "%s", inc[0]
		end
		$msg.printf "\n"
	end

	def list_command_client(client)
		if @address != client
			$msg.printf "##### #{client}:#{@address} #####\n"
		else
			$msg.printf "##### #{client} #####\n"
		end
		list_command_client_key(client, 'includes')
		list_command_client_key(client, 'excludes')
		list_command_client_key(client, 'opts', " ")
		list_command_client_key(client, 'ninc', nil)
	end

	def list_command_pp(key, value)
		$msg.printf "%12s=%s\n", key, value
	end

	def list_command_global_settings
		return if @global_settings
		@global_settings = true

		$msg.printf "##### Global settings #####"
		list_command_pp("profile", @options.profile)
		if @dest.length == 0
			$msg.warn "backup destination not set"
		else
			list_command_pp("dest", @dest)
		end
		list_command_pp("ssh opts", @sshopts["global"])
		list_command_pp("email", @options.email) if @options.email
		list_command_pp("smtp server", @options.smtp) if @options.smtp
		$msg.puts ""
		@global_settings = true
	end

	def list_command
		if @options.verbose
			$msg.info "##### Configuration #####"
			@config.dump
		end

		list_command_global_settings

		return if @options.global

		list_command_client(@client)
	end

	def history_command_display(cli, hist)
		return if hist.length == 0

		print_command

		if @options.hist_index != nil
			$msg.printf "%s\n", "#{cli}:#{@options.hist_index}: #{hist[0]}"
			logf = get_client_dir(@client, false, hist[0], "rubac.log.yaml")
			if not File.exist?(logf)
				$msg.err "opening #{logf}"
				return
			end

			log = File.open(logf) { |yf| YAML::load(yf) }
			log.each do |line|
				$msg.printf "%s\n", line
			end
			return
		end

		hist.each_index do |i|
			$msg.printf "%s\n", "#{cli}:#{i}: #{hist[i]}"
		end
	end

	def history_command_get_history(cli)
		entries = []
		(0..@ninc).to_a.each do |n|
			next if @options.hist_index != nil and @options.hist_index != n
			name = @config.get_client_incrementals(cli, n)
			break if name.length == 0
			entries << name
		end

		cdir = get_client_dir(cli, false)
		return entries if not File.exist?(cdir)

		Dir.chdir(cdir)
		entries.concat(Dir.glob('rubac.snapshot.*'))
		entries
	end

	def history_command
		hist = []
		# look in /bdest/profile/client/rubac.date,.../rubac.log.yaml
		hist = history_command_get_history(@client)
		history_command_display(@client, hist)
	end

	def search_command_pp(label, value, fmt="%s")
		$msg.printf("%8s=#{fmt}\n", label, value)
	end

	def search_command_history(hist, pattern)

		$msg.puts "Searching #{hist} for '#{pattern}'"

		pbasedir = false
		basedir= get_client_dir(@client, false, hist)
		logf = File.join(basedir, "rubac.log.yaml")
		if not File.exist?(logf)
			$msg.err "opening #{logf}"
			return
		end

		log = File.open(logf) { |yf| YAML::load(yf) }
		log.each do |line|
			next if not line[/#{pattern}/i]
			fpath = File.join(basedir, line)

			if not File.exist?(fpath)
				$msg.err "backup log not found #{fpath}"
				next
			end

			fstat = File.lstat(fpath)
			# record found file inodes to eliminate duplicates
			next if @inodes.has_key?(fstat.ino)
			@inodes[fstat.ino] = fstat.nlink

			if pbasedir == false
				$msg.puts "basedir=#{basedir}"
				pbasedir = true
			end

			@options.restore << line if @options.search_restore

			$msg.puts line
			next if not @options.verbose

			search_command_pp("type", fstat.ftype)
			if fstat.file?
				search_command_pp("md5sum", Digest::MD5.file(fpath).hexdigest)
			end
			search_command_pp("size", fstat.size)
			search_command_pp("atime", fstat.atime)
			search_command_pp("mtime", fstat.mtime)
			search_command_pp("ctime", fstat.ctime)
			search_command_pp("uid:gid", "#{fstat.uid}:#{fstat.gid}")
			search_command_pp("perm", fstat.mode, "%o")
			search_command_pp("ino", fstat.ino)
		end

		restore_command if @options.search_restore
	end

	def search_command
		print_command
		hist = []
		if @select
			hist << @select
		else
			hist = history_command_get_history(@client)
		end

		return if hist.length == 0

		@inodes = {}
		@options.search.each do |pattern|
			hist.each_index do |i|
				search_command_history(hist[i], pattern)
			end
		end
	end

	def prune_command_prune(host, hist, index)
		$msg.info "Pruning #{host}:#{hist[index]} for history index #{index}"

		if index < 0 or index >= hist.length
			err "Invalid index=#{index} with hist.length=#{hist.length}"
			$ret = 1
			return 1
		end

		# setup flags for delete
		rm_flags = { :force => true, :verbose => true }
		rm_flags.merge!( :noop => true ) if @options.dry_run 

		j = hist.length-1
		if index < j
			a = (index..j).to_a
			a.each do |x|
				y = x+1
				break if y == hist.length
				$msg.info "#{x}:#{hist[y]}"
				@config.set_client_incremental(host, x, hist[y])
			end
			@config.set_client_incremental(host, j, "")
		else
			@config.set_client_incremental(host, index, "")
		end

		accept_signals(false)

		prune=get_client_dir(host, false, hist[index])
		if File.exist?(prune)
			$msg.info "Remove #{index}:#{hist[index]}:#{prune}"
			FileUtils.rm_r(prune, rm_flags)
			status = $?
		else
			$msg.warn "Prune backup #{prune} not found"
		end
		@config.save(@options.dbname, @options.datadir) if not @options.dry_run

		accept_signals(true)
		return $status
	end

	def prune_command

		if @select == nil
			$msg.err "specify which backup to delete with --select"
			$ret = 1
			return 1
		end

		hist = []
		hist = history_command_get_history(@client)

		if hist.length < 1
			$msg.err "No history found for #{@client}"
			$ret = 1
			return 1
		end

		index = nil
		hist.each_index do |i|
			if hist[i] == @select
				index = i
				break
			end
		end

		$msg.die "Selected backup #{@select} not found" if index == nil

		$msg.info "Deleting #{hist[index]} with index=#{index}"

		prune_command_prune(@client, hist, index)
		return $?
	end

	def restore_command_cmd(cmd)
		$msg.info "cmd=#{cmd}"
	end

	def restore_command_validate_restore_from(path)
		lines = []
		File.open(path, 'r').each_line do |line|
			line.chop!
			line.split(",").each do |l|
				l.strip!
				# skip comments
				next if l[0].chr == "#"
				# restore paths must be absolute
				next if l[0].chr != "/"
				$msg.info "restoring #{l}"
				lines << l
			end
		end
		$msg.warn "restore-from #{path} is empty" if lines.length == 0
		lines
	end

	def restore_command_write_restore_from(restore)
		path = File.join(@options.tmp, get_backup_dirname("rubac.restore_from.", ".dat"))
		File.open(path, 'w') do |fd|
			restore.each do |line|
				line.split(",").each do |l|
					l.strip!
					fd.puts(l)
					$msg.info "#{l} >> #{path}"
				end
			end
		end
		path
	end

	def restore_command
		print_command

		host = @client
		host = nil if host == "localhost" or host == "127.0.0.1"

		# @options.select may contain the backup source
		if @select
			source = @select
		else
			source = @config.get_client_incrementals(@client, 0)
		end

		if source.length == 0
			$msg.err "nothing to restore for client=#{@client}"
			return
		end

		$msg.debug "Backup source = #{source}"

		dest = ""

		@options.restore_to = File.join(@options.tmp, "rubac", @client) if not @options.restore_to

		# restore_to can include a host [host:]/path
		adest = @options.restore_to.split(":",2)
		dest = host + ":" if adest.length == 1 and host
		dest << @options.restore_to

		bsource = get_client_dir(@client, false, source)
		$msg.info "cd #{bsource}"
		# TODO check that bsource exists
		Dir.chdir(bsource)

		if @options.restore.length > 0
			@options.restore_from = restore_command_write_restore_from(@options.restore)
			#cmd="rsync #{@sshopts["restore"]} #{restore[1..-1]} #{dest}"
		elsif @options.restore_from.length > 0
			restore_command_validate_restore_from(@options.restore_from)
		else # @options.restore_from.length == 0
			$msg.err "nothing to restore"
			$ret = 1
			return
		end

		cmd = "rsync #{@sshopts["restore"]} --files-from=#{@options.restore_from} #{bsource} #{dest}"
		$msg.info cmd

		# write stderr to stdout
		cmd << " 2>&1"
		p = IO.popen(cmd)
		while (line = p.gets)
			line.chop!
			out = File.join(dest, line)
			if line[/\sis uptodate$/]
				$msg.log out
			elsif line[/\/$/]
				lastdir=line
			elsif lastdir and line[/^#{lastdir}/]
				$msg.info out
			else
				$msg.info "$#{line}"
			end
		end
		## TODO get status of command??
		p.close
		status=$?.exitstatus
		#p status
		#out = %x{#{cmd}}
		#status = $?.exitstatus
		#$msg.info out
		if status != 0
			$msg.err "command failed %Q(#{cmd})"
		end
	end

	def version_command
		ver = @config.version
		$msg.puts "#{File.basename(__FILE__)} " + ver
	end
    
	def process_command_client(client)
		@client = client
		@includes = @config.get_client_includes(client)
		@excludes = @config.get_client_excludes(client)
		@address = @config.get_client_address(client)
		@ninc = @config.get_client_ninc(client)

		@options.compress = @config.get_client_key_value(client, "compress")

		@sshopts["#{client}"] = @config.get_client_opts(client)
		@sshopts["#{client}"] << " --compress" if @options.compress == true

		@select = nil
		case @options.select
		when @options.select[/[0-9].*/]
			@select = @config.get_client_incrementals(client, @options.select)
			$msg.die "selected backup #{@options.select} not found" if @select.length == 0
			$msg.info "Selected backup ##{@options.select} #{@select}"
		when "newest"
			@select = @config.get_client_incrementals(client, 0)
		when "oldest"
			(0..@ninc).to_a.reverse.each do |i|
				s = @config.get_client_incrementals(client, i)
				if s.length > 0
					@select = s
					break
				end
			end
		else
			@select = @options.select
		end if @options.select
		@select = nil if @select and @select.length == 0

		status=eval @options.cmd
		status
	end

	def process_command_clients(notify=false)
		subject = "#{@options.cmd}: #{@options.profile}:#{@options.client.join(",")}"
		@options.client.each do |client|
			$msg.set_client(client)
			$msg.debug ">>>>> Running #{@options.cmd} for #{client}"
			process_command_client(client)
			$msg.debug "<<<<< Done running #{@options.cmd} for #{client}"
			$msg.set_client
		end
		if notify == true
			du_cmd="df -lm #{@dest}"
			$msg.print "\n" + `#{du_cmd}` + "\n"
			$msg.print "\nSee #{$msg.privlog_path} for details\n"

			$msg.puts "Send notify=#{notify} with subject=#{subject}"
			$msg.send_notify(subject)
		end
	end

	def process_command
		@dest = @config.get_global_dest

		if @dest.length > 0
			check_backup_destination(@dest)
		else
			$msg.warn "backup destination not set"
		end

		@sshopts["global"]  << " --dry-run" if @options.dry_run
		@sshopts["restore"] << " --dry-run" if @options.dry_run

		#TODO @cmdptr = method( :help_command ) 
		#TODO execute with
		#TODO @cmdptr.call

		case @options.cmd
		when "version_command"
			# already done above
		when "help_command", "usage_command", "examples_command"
			eval @options.cmd
		when "list_command", "history_command", "search_command"
			process_command_clients(false)
		when "run_command", "snapshot_command", "prune_command", "restore_command"
			$msg.die "Must specify at least one client" if @options.all == true
			$msg.die "backup destination not set" if not File.exist?(@dest)
			process_command_clients(true)
		else
			#$msg.puts "huh? #{Config::CONFIG['host_os']}"
			@options.client.each do |client|
				$msg.info "#{client}:includes=#{@config.get_client_includes(client)}" if @options.includes
				$msg.info "#{client}:excludes=#{@config.get_client_excludes(client)}" if @options.excludes
				$msg.info "#{client}:opts=#{@config.get_client_opts(client)}" if @options.opts
			end
		end

	end

	#def process_standard_input
	#	input = @stdin.read      
		# TO DO - process input

		# [Optional]
		# @stdin.each do |line| 
		#  # TO DO - process each line
		# end
	#end
end

$signal_exit = false

def trapSigTerm
	$stderr << "\nTERM signal ignored\n"
	$signal_exit = true
end

def trapSigInt
	$stderr << "\nINT signal ignored\n"
	$signal_exit = true
end

def trapSigHup
	$stderr << "\nHUP signal ignored\n"
	$signal_exit = true
end

end
