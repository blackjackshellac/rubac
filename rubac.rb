#!/usr/bin/ruby
#
# == Synopsis 
#   A simple backup program for ruby powered by rsync that can save
#   multiple backup profiles between uses.
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
#   -c, --client[=HOST]   Client to backup (default is local)
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
# == Environment Variables ==
#
# RUBAC_DATADIR - set the database directory
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
require 'rubac_db'

#
# rsync version must be at least 2.5.6 for --link-dest option
#

class Rubac
	VERSION = '0.0.1'

	attr_reader :options

	def initialize(arguments, stdin)
		@arguments = arguments
		@stdin = stdin
		@revision = "$Rev: 20 $"
			      
		# Set defaults
		@options = OpenStruct.new
		@options.global = false
		@options.profile = "rubac"

		if ENV['RUBAC_DATADIR']
			@options.data_dir = ENV['RUBAC_DATADIR']
		else
			@options.data_dir = "/etc/rubac"
			ENV['RUBAC_DATADIR'] = @options.data_dir
		end

		@options.verbose = false
		@options.quiet = false
		@options.include = ""
		@options.exclude = ""
		@options.opts = ""
		@options.run = false

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

			puts "\nFinished at #{DateTime.now}" if @options.verbose

			puts "###"
			puts @options
			puts "###"

		else
			output_usage
		end
	end

	protected

	def parsed_options?

		# Specify options
		opts = OptionParser.new 
		opts.on('-v', '--version', "Print version")    { output_version ; exit 0 }
		opts.on('-V', '--verbose', "Run verbosely")    { @options.verbose = true }  
		opts.on('-q', '--quiet',   "Run quietly")      { @options.quiet = true }

		opts.on('-DPATH', '--data_dir PATH', "Database directory") do |dir|
			@options.data_dir = dir
		end

		opts.on('-iPATH', '--include PATH', "Add include path") do |inc|
			@options.include = inc
		end

		opts.on('-xPATH', '--exclude PATH', "Add exclude path") do |exc|
			@options.exclude = exc
		end
		opts.on('-PNAME', '--profile NAME', "Apply opts to specified profile") do |profile|
			@options.profile = profile
		end
		# TO DO - add additional options

		opts.on('-h', '--help',    "Print help") do   #   { output_help }
			output_help
		end

		opts.on('-r', '--run', "Run the backup") do
			@cmd="run"
		end
		opts.on('-t', '--list', "List the backup options") do
			@cmd="list"
		end

		puts "###"
		puts @options
		puts "###"

		opts.parse!(@arguments) rescue return false

		process_options
		true      
	end

	# Performs post-parse processing on options
	def process_options
		@options.verbose = false if @options.quiet
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
		puts "arguments =  #{@arguments.length} \n"
		true if @arguments.length >= 1 
	end

	# Setup the arguments
	def process_arguments
		# TO DO - place in local vars, etc
	end
    
	def output_help
		output_version
		RDoc::usage() #exits app
	end
    
	def output_usage
		RDoc::usage('usage') # gets usage from comments above
	end
    
	def output_version
		puts "#{File.basename(__FILE__)} version #{VERSION}"
	end
    
	def process_command
		# TO DO - do whatever this app does

		#process_standard_input # [Optional]

		db = Rubac_db.new(File.join(@options.data_dir, "szmb.db"))
		db.test

		@cmd="ls -l /home/rubac/linguini/default"
		puts @cmd
		listing=`#{@cmd}`
		p $?.exitstatus
		puts listing
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

