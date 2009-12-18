#!/usr/bin/ruby
#
# == Synopsis 
#   
#   Mixin for info, warning, error messages
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
#

module Szmsg

	def info(msg)
		puts "#{msg}"
	end

	def warn(msg)
		puts "Warning: #{msg}"
	end

	def err(msg)
		puts "Error: #{msg}"
		false
	end

	def die(msg)
		err(msg)
		exit(1)
	end
end

