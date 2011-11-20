
module Rubac
  # create a stack with a limited number of entries
  class Stack
    attr_reader :elements
  
    def initialize(elements)
      @elements = elements
      @stack = Array.new
    end
  
    # push an item, delete the entry at the bottom of the stack 
    def push(item)
      return if item.nil?
      @stack.delete_at(0) if @elements and @stack.length == @elements
      @stack.push(item)
    end
  
    def pop
      @stack.pop
    end
  
    def each
      @stack.each { |item| yield item }
    end
  end

end