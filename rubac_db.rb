#!/usr/bin/ruby
#
# == Synopsis 
#   
#   Database class for the rubac backup program to store backup
#   profiles, options, globals, etc.
#
# == 
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
# $Id: rubac_db.rb 36 2009-12-14 17:11:06Z steeve $

require 'sqlite3'
require 'pp'

class Rubac_db

	def initialize(dbname)

		# define globals hash
		@globals = Array.new
		@globals << { 
			'major_vers' => "major_vers",
			'minor_vers' => "minor_vers",
			'revision' => "revision",
			'client' => "client",
			'opts' => "opts"
		}
		@globals << {
			'major_vers' => "0",
			'minor_vers' => "3",
			'revision' => "$Rev$",
			'client' => "localhost",
			'opts' => ""
		}

		# first array element is the table column name
		# if client is nil, use global client
		@includes = Array.new
		@includes << { 'client' => "client", 'path' => "path", 'opts' => "opts", 'excludes' => "excludes" }
		@includes << { 'client' => nil, 'path' => "/home/etienne", 'opts' => "--delete", 'excludes' => '*/.gvfs/' }

		# these excludes are global ...
		@excludes = Array.new
		@excludes << { 'client' => "client", 'path' => "path" }
		@excludes << { 'client' => nil, 'path' => '*/.mozilla/**/Cache/' }

		pp ( @globals )
		pp ( @includes )
		pp ( @excludes )

		@dbname=dbname
		begin
			puts "Initializing #{@dbname}"
			@db = SQLite3::Database.new( @dbname )
		rescue
			puts "Failed to initialize #{@dbname}"
		end

		if not File.exist?(@dbname)
			create_globals
			create_includes
			create_excludes
		else
			create_globals if not table_exists?("globals")
			create_includes if not table_exists?("includes")
			create_excludes if not table_exists?("excludes")
		end

	end

	def select_all(table)
		sql = "select * from #{table}"
		begin
			@db.execute(sql)
		rescue
			puts "Select failed on table #{table}"
			false
		end
	end

	def table_exists?(table)
		begin
			t=@db.execute("select name from sqlite_master where type='table' and tbl_name='"+table+"'")
			if t.empty?
				puts "table #{table} is empty"
				false
			else
				puts "table #{table} is found"
				true
			end
		rescue
			puts "Failed to query sqlite_master for table=#{table}"
		end
	end

	#
	# Create the specified table with the sql provided
	#
	def batch_create(sql, table)
		puts "Creating table \"#{table}\" with \"#{sql}\""
		begin
			@db.execute_batch(sql)
		rescue SQLite3::SQLException
			puts "Error creating table #{table}: SQL error"
			false
		rescue
			puts "Error creating table #{table}"
			false
		end
	end

	def create_globals
		sql = <<SQL
		create table globals (
			major_vers INTEGER,
			minor_vers INTEGER,
			client TEXT,
			opts   TEXT
		);
		insert into globals (major_vers, minor_vers, client, opts)
			values (#{@globals["major_vers"]},#{@globals["minor_vers"]},
				"localhost", "" );
SQL
		batch_create(sql, "globals")
	end

	def create_excludes
		sql = <<SQL
		create table excludes (
			client TEXT,
			path TEXT
		);

SQL
		batch_create(sql, "excludes")
	end

	def create_includes
		sql = <<SQL
		create table includes (
			client TEXT,
			path TEXT, 
			opts TEXT
		);

SQL
		batch_create(sql, "includes")
	end

	#
	# Update the given table column with the specified value
	#
	# update
	#   * table - the table to be updated
	#   * column - the column in the table to be updated
	#   * value - the value to be updated
	#
	# bool success/fail
	# 
	def update(table, column, value)
		sql = "update #{table} set #{column}='#{value}';"
		begin
			@db.execute(sql)
		rescue
			puts "Error: sql failure #{sql}"
			false
		end
	end

	#
	# Insert the given values into the specified columns in the table
	#
	# insert
	#    * table - the table to be inserted
	#    * columns - the comma delimited list of columsn to be inserted
	#    * values - the comma delimited list of values to be inserted
	#
	# bool success/fail
	#
	def insert(table, columns, values)
		sql = "insert into #{table} (#{columns}) values #{values};"
		begin
			@db.execute(sql)
		rescue
			puts "Error: sql failure #{sql}"
			false
		end
	end

	def test

		@db.execute( "select * from globals;" ) do |row|
			p row
		end

		begin
			@db.execute( "select * from includes" ) do |row|
				p "path=#{row[0]}, opts=#{row[1]}"
			end
		rescue SQLite3::SQLException
			puts "Invalid SQL"
		end

		@db.execute( "select * from excludes" ) do |row|
			p row
		end

		@db.close

	end

end

