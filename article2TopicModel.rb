require 'rubygems'

class Article2TopicModel

	def create_file
		scrape_file = File.new("#{@new_directory}/#{title}.txt","w")
	end
	
	def open_file(path)	
		file_array = []
		File.open(path, "r") do |f|
  			f.each_line do |line|
  				unless line.strip.empty? || line.strip.downcase == "by"
	    			file_array << line.strip
    			end	
    		end	
  		end
  		puts file_array[1]
	end	

end


#rf = Article2TopicModel.new
#rf.open_file