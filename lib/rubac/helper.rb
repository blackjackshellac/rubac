
module Rubac
  
  #
  # Extract help from the given file header comments
  #
  # Sections are delimited by " == Section Name ..."
  #
  class HeaderHelp
    attr_reader :sections
  
    def initialize(file)
      @sections=Hash.new { |h,k| h[k]=[] }
  
      File.open(file, 'r') { |f|
        section=nil
        f.each_line { |line|
          #line.chomp!
          next unless line[/^#([^!].*)/]
          line=$1
          if line[/^\s*={2,3}\s+(.*?)\s*=*\s*$/]
            section=$1
            #puts  "New section: #{section}"
          end
          next if section.nil?
          @sections[section] << line
        }
      }
    end
  
    def list
      @sections.each { |k,v| puts "key="+k }
    end
  
    def print(secs)
      case secs
      when Array
        print_array(secs)
      when String
        print_section(secs)
      end
    end
  
    private
  
    def print_section(section)
      return unless @sections.has_key?(section)
      @sections[section].each { |line| puts line }
    end
  
    def print_array(secs)
      secs.each { |s|
        print_section(s)
      }
    end
  end

end
