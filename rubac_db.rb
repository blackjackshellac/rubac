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
# $Id$

require 'sqlite3'

class Rubac_db

	def initialize(dbpath)
		@db_version = Hash[ "major", "0", "minor", "2" ]
		puts "major=" + @db_version['major']
		puts "minor=" + @db_version['minor']

		@dbpath=dbpath
		begin
			puts "Initializing #{@dbpath}"
			@db = SQLite3::Database.new( @dbpath )
		rescue
			puts "Failed to initialize #{@db}"
		end

		create_globals if not table_exists?("globals")
		create_includes if not table_exists?("includes")
		create_excludes if not table_exists?("excludes")

		@globals = select_all("globals")
		p @globals
		@excludes = select_all("excludes")
		p @excludes
		@includes = select_all("includes")
		p @includes
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
			minor_vers INTEGER
		);
		insert into globals ( #{@db_version["major"]}, #{@db_version["minor"]} );
SQL
		batch_create(sql, "globals")

		@db.execute("drop table globals;")

		#sql = "insert into globals ( " + @db_version['major'] + "," + @db_version['minor'] + " );"
	end

	def create_excludes
		sql = <<SQL
		create table excludes (
			path TEXT
		);

SQL
		batch_create(sql, "excludes")
	end

	def create_includes
		sql = <<SQL
		create table includes (
			path TEXT, 
			opts TEXT
		);

SQL
		batch_create(sql, "includes")
	end

	def test

		puts "Feck" if not table_exists?("noincludes")

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

