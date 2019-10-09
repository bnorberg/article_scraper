require 'rubygems'
require 'koala'
require 'csv'
require 'open-uri'
require 'json'
require 'date'
require 'mechanize'
require 'webshot'
require 'disqus_api'
require 'streamio-ffmpeg'
require 'youtube-dl.rb'

class ArticleScraper

	def initiate_mechanize
		@mechanize = Mechanize.new
	end	

	def initiate_webshot
		@ws = Webshot::Screenshot.instance
	end	

	def initiate_fb_client
		@graph = Koala::Facebook::API.new(ARGV[0])
		Koala.config.api_version = "v2.2"
	end

	def initiate_disqus
		DisqusApi.config = {api_secret:'add secret',
                    api_key: 'add key',
                    access_token: 'add token'}
	end	

	
	def create_disqus_comments_csv(story_comments, title)
		disqus_comments_csv = "#{@directory}/#{title}_comments.csv"
		CSV.open(disqus_comments_csv, 'ab') do |csv|
			file = CSV.read(disqus_comments_csv,:encoding => "iso-8859-1",:col_sep => ",")
			if file.none?
				csv << ["comment_id", "response_to_id", "author", "author_reputation", "create_date", "create_time", "message","likes", "dislikes", "thread_id"]
			end
			story_comments.each do |comment|
				if !comment['media'].empty?
					media_number = 0
					comment['media'].each do |m|
						media_number += 1
						url = m['urlRedirect']
						if !url.include?("facebook.com") || !url.include?(twitter.com)
							download_object("#{@directory}/comment_#{comment['id']}_media#{media_number}_#{url.split("/").last}", url)
						else
							social_media_screencapture(url, "#{@directory}/comment_#{comment['id']}_media#{media_number}_#{url.split("/").last}")	
						end
					end	
				end	
				csv << [comment['id'], comment['parent'], comment['author']['name'], comment['author']['rep'], DateTime.parse(comment['createdAt']).strftime("%m-%d-%Y"), DateTime.parse(comment['createdAt']).strftime("%H:%M:%S"), comment['raw_message'], comment['likes'] , comment['likes'], comment['thread']]
			end	
  		end
	end

	def create_facebook_comments_csv(story_comments, title)
		fb_comments_csv = "#{@new_directory}/#{title}_comments.csv"
		CSV.open(fb_comments_csv, 'ab') do |csv|
			file = CSV.read(fb_comments_csv,:encoding => "iso-8859-1",:col_sep => ",")
			if file.none?
				csv << ["comment_id", "author", "create_date", "create_time", "message", "likes", "response_id", "response_author", "response_create_date", "response_create_time", "response_message", "response_likes"]
			end
			story_comments.each do |comment_page|
				comment_page.each do |comment|
					comment_comments = @graph.get_connection(comment['id'], 'comments')
					if !comment_comments.empty?
						csv << [comment['id'], comment['from']['name'], DateTime.parse(comment['created_time']).strftime("%m-%d-%Y"), DateTime.parse(comment['created_time']).strftime("%H:%M:%S"), comment['message'], comment['like_count'], comment_comments.first['id'], comment_comments.first['from']['name'], DateTime.parse(comment_comments.first['created_time']).strftime("%m-%d-%Y"), DateTime.parse(comment_comments.first['created_time']).strftime("%H:%M:%S"), comment_comments.first['message'], comment_comments.first['like_count']]
					else		
						csv << [comment['id'], comment['from']['name'], DateTime.parse(comment['created_time']).strftime("%m-%d-%Y"), DateTime.parse(comment['created_time']).strftime("%H:%M:%S"), comment['message'], comment['like_count']]
					end	
				end	
			end	
  		end
	end

	def download_object(name, object)
		File.open(name,'wb') do |fo|
			fo.write open(object,{ssl_verify_mode: OpenSSL::SSL::VERIFY_NONE}).read
		end
	end

	def article_screencapture(link, id)
		@ws.capture link, "#{@new_directory}/#{id}_screencapture.png", width: 2000, height: 12000, timeout: 10
	end	

	def social_media_screencapture(link, id)
		@ws.capture link, "#{@directory}/#{id}_screencapture.png", width: 800, height: 800, timeout: 60
	end	

	def check_directory_exists(directory)
		if !Dir.exists?(directory)
			Dir.mkdir(directory, 0755)
			puts "Made dir: #{directory}"
		end
		filecount = Dir["#{directory}/*"].length
		file_number = filecount + 1
		@new_directory = "#{directory}/#{file_number}"
		Dir.mkdir(@new_directory, 0755)
		puts "Made dir: #{@new_directory}"
	end

	def download_tumblr_image(image_source, id)
		if image_source.include?(".jpg")
			name = "#{@directory}/tumblr_#{id}.jpg"
		elsif image_source.include?(".mp4")
			name = "#{@directory}/tumblr_#{id}.mp4"
		elsif image_source.include?(".gif")
			name = "#{@directory}/tumblr_#{id}.gif"	
		end
		download_object(name, image_source)
	end	

	def youtube_download(link)
		outfile = "#{@directory}/#{link.split("wathch?v=")[1]}.mkv"
		video = YoutubeDL.download link, output: outfile
		convert_video(outfile)
		create_youtube_info_csv(video, outfile)
	end	

	def create_youtube_info_csv(video, outfile)
		video_info_csv = "#{outfile.gsub(".", "_")}.csv"
		CSV.open(video_info_csv, 'ab') do |csv|
			file = CSV.read(video_info_csv,:encoding => "iso-8859-1",:col_sep => ",")
			if file.none?
				csv << ["title", "description", "author", "uploader", "upload_date", "views", "dislikes", "likes"]
			end
			csv << [video.information[:fulltitle], video.information[:description], video.information[:creator], video.information[:uploader], video.information[:upload_date], video.information[:view_count], video.information[:dislike_count], video.information[:like_count]]
  		end
	end	

	def convert_video(file)
		movie = FFMPEG::Movie.new(file)
		movie.transcode("#{file}".gsub("mkv", "mp4"))
	end	

	def call_mechanize(link)
		begin
			@mechanize.get(link)
		rescue Exception => e
  			page = e
		end	
	end	

	def scrape_article(link)
		page = call_mechanize(link)
		puts page.title
		if !page.title.include?("Page Not Found")
			if link.include?("newsobserver")
				@directory = "#{ARGV.last}/newsobserver"
				check_directory_exists(@directory)
				scrape_no(page)
			elsif link.include?("dukechronicle.com") || link.include?("chron.it")
				@directory = "#{ARGV.last}/dukechronicle"
				check_directory_exists(@directory)
				scrape_chronicle(page)			
			elsif link.include?("heraldsun")
				@directory = "#{ARGV.last}/heraldsun"
				check_directory_exists(@directory)
				scrape_herald_sun(page)
			elsif link.include?("wral.com")
				@directory = "#{ARGV.last}/wral"
				check_directory_exists(@directory)
				scrape_wral(page)
			elsif link.include?("abc11.com")
				@directory = "#{ARGV.last}/abc11"
				check_directory_exists(@directory)
				scrape_abc11(page)
			elsif link.include?("wncn.com")
				@directory = "#{ARGV.last}/wncn"
				check_directory_exists(@directory)
				scrape_wncn(page)
			elsif link.include?("csmonitor.com")
				@directory = "#{ARGV.last}/christian_monitor"
				check_directory_exists(@directory)
				scrape_christian_monitor(page)
			elsif link.include?("college.usatoday")
				@directory = "#{ARGV.last}/usatoday_college"
				check_directory_exists(@directory)	
				scrape_usatoday_college(page)
			elsif link.include?("wibailoutpeople.org") || link.include?("dsws2016.wordpress")
				@directory = "#{ARGV.last}/wordpress-sites"
				check_directory_exists(@directory)
				scrape_wordpress(page)
			elsif link.include?("insidehighered")
				@directory = "#{ARGV.last}/insidehighered"
				check_directory_exists(@directory)
				scrape_insidehighered(page)	
			elsif link.include?("http://www.chronicle.com/")
				@directory = "#{ARGV.last}/chronicleofhighered"
				check_directory_exists(@directory)
				scrape_chronicle_higher_ed(page)
			elsif link.include?("http://www.washingtontimes.com/")
				@directory = "#{ARGV.last}/washingtontimes"
				check_directory_exists(@directory)
				scrape_washingtontimes(page)
			elsif link.include?("http://www.foxnews.com/")
				@directory = "#{ARGV.last}/foxnews"
				check_directory_exists(@directory)		
				scrape_foxnews(page)
			elsif link.include?("http://atlantablackstar.com/")
				@directory = "#{ARGV.last}/atlantablackstar"
				check_directory_exists(@directory)		
				scrape_atlantablackstar(page)	
			elsif link.include?("liberationnews")
				@directory = "#{ARGV.last}/liberationnews"
				check_directory_exists(@directory)
				scrape_liberation_news(page)
			elsif link.include?("washingtonpost")
				@directory = "#{ARGV.last}/washinghtonpost"
				check_directory_exists(@directory)
				scrape_washingtonpost(page)
			elsif link.include?("technicianonline")
				@directory = "#{ARGV.last}/technicianonline"
				check_directory_exists(@directory)
				scrape_technician(page)	
			elsif link.include?("bet.com")
				@directory = "#{ARGV.last}/bet"
				check_directory_exists(@directory)
				scrape_bet(page)
			elsif link.include?("colorlines")
				@directory = "#{ARGV.last}/colorlines"
				check_directory_exists(@directory)
				scrape_colorlines(page)
			elsif link.include?("huffingtonpost")
				@directory = "#{ARGV.last}/huffingtonpost"
				check_directory_exists(@directory)	
				scrape_huffingtonpost(page)
				create_huffingtonpost_csv(page)
			elsif link.include?("time.com")
				@directory = "#{ARGV.last}/time"
				check_directory_exists(@directory)	
				scrape_time(page)
			elsif link.include?("indyweek")
				@directory = "#{ARGV.last}/indyweek"
				check_directory_exists(@directory)	
				scrape_indy(page)	
			elsif link.include?("mic.com")
				@directory = "#{ARGV.last}/mic"
				check_directory_exists(@directory)	
				scrape_mic(page)		
			elsif link.include?("newsone.com")
				@directory = "#{ARGV.last}/newsone"
				check_directory_exists(@directory)	
				scrape_newsone(page)	
			elsif link.include?("workers.org")
				@directory = "#{ARGV.last}/workers_org"
				check_directory_exists(@directory)
				scrape_workers_org(page)	
			elsif link.include?("independent.co.uk")
				@directory = "#{ARGV.last}/independent_uk"
				check_directory_exists(@directory)
				scrape_independent(page)
			elsif link.include?("twcnews.com")
				@directory = "#{ARGV.last}/twcnews"
				check_directory_exists(@directory)
				scrape_twc(page)
			elsif link.include?("http://gawker.com/")
				@directory = "#{ARGV.last}/gawker"
				check_directory_exists(@directory)
				scrape_gawker(page)
			elsif link.include?("dailywire.com")
				@directory = "#{ARGV.last}/dailywire"
				check_directory_exists(@directory)
				scrape_dailywire(page)
			elsif link.include?("theguardian.com")
				@directory = "#{ARGV.last}/guardian"
				check_directory_exists(@directory)
				scrape_guardian(page)		
			elsif link.include?("tumblr")
				@directory = "#{ARGV.last}/tumblr"
				check_directory_exists(@directory)
				id = "#{link}".split("/").last
				image_source = page.at('img#content-image')['data-src']
				download_tumblr_image(image_source, id)
			elsif link.include?("dailytarheel")
				@directory = "#{ARGV.last}/dailytarheel"
				check_directory_exists(@directory)
				scrape_dailytarheel(page)	
			elsif link.include?("opensource.com")
				@directory = "#{ARGV.last}/opensource_com"
				check_directory_exists(@directory)
				scrape_opensource_com(page)	
				create_opensource_csv(page)
			elsif link.include?("edsurge.com")
				@directory = "#{ARGV.last}/edsurge"
				check_directory_exists(@directory)
				scrape_edsurge(page)
				create_edsurge_csv(page)
			elsif link.include?("digitalpedagogylab.com")
				@directory = "#{ARGV.last}/hybridpedagogy"
				check_directory_exists(@directory)
				scrape_hybridpedagogy(page)	
				create_hybridpedagogy_csv(page)
			elsif link.include?("blog.okfn.org")
				@directory = "#{ARGV.last}/okfn"
				check_directory_exists(@directory)
				scrape_openknowledge(page)
				create_openknowledge_csv(page)	
			elsif link.include?("www.hewlett.org")
				@directory = "#{ARGV.last}/hewlett"
				check_directory_exists(@directory)
				scrape_hewlett(page)	
				create_hewlett_csv(page)
			elsif link.include?("creativecommons.org")
				@directory = "#{ARGV.last}/creativecommons"
				check_directory_exists(@directory)
				scrape_creativecommons(page)	
				create_creativecommons_csv(page)	
			elsif link.include?("nytimes.com")
				@directory = "#{ARGV.last}/nyt"
				check_directory_exists(@directory)
				scrape_newyorktimes(page)	
				create_newyorktimes_csv(page)					
			elsif link.include?("medium.com")	
				@directory = "#{ARGV.last}/medium_com"
				check_directory_exists(@directory)
				scrape_medium_com(page)
				create_medium_csv(page)	
			else
				# only screenshot
				@directory = "#{ARGV.last}/other_articles"
				check_directory_exists(@directory)
			end
		else
			@directory = "#{ARGV.last}/articles_not_found"
			check_directory_exists(@directory)
			scrape_file = File.new("#{@directory}/#{link.last.delete("|,.:").gsub(" ", "-")}.txt","w")
			scrape_file.puts(page.title)
		end
		article_screencapture(link, link.split("/").last.delete("|,.:").gsub(" ", "-"))
	end

	def scrape_liberation_news(page)
		title = "#{page.title}".delete("|,.:").gsub(" ", "-")
		scrape_file = File.new("#{@directory}/#{title}.txt","w")
		scrape_file.puts(page.at('div.article-body').text.strip)
		image = page.at('img.full-image-format')
		if !image.nil?
			if page.uri.to_s.include?("https")
				image_source = image['src'].prepend("https:")
			else
				image_source = image['src'].prepend("http:")
			end		
			image_name = "#{@directory}/#{title}_image.jpg"
			download_object(image_name, image_source)	
		end		
	end


	def scrape_christian_monitor(page)
		title = "#{page.title}".delete("|,.:").gsub(" ", "-")
		scrape_file = File.new("#{@directory}/#{title}.txt","w")
		page.at('div#ui-main-column').css('script').remove
		page.at('div#ui-main-column').css('style').remove
		page.at('div#ui-main-column').css('div#sticky-nav').remove
		page.at('div#ui-main-column').css('h3.story_headline').remove
		page.at('div#ui-main-column').css('div.bookmarking_wrapper').remove
		page.at('div#ui-main-column').css('li.video.disabled').remove
		page.at('div#ui-main-column').css('div.caption_bar').remove
		page.at('div#ui-main-column').css('div#image-nav').remove
		page.at('div#ui-main-column').css('div.promo_link_wrapper').remove
		page.at('div#ui-main-column').css('div.story_thumbnail').remove
		page.at('div#ui-main-column').css('div#story-embed-column').remove
		page.at('div#ui-main-column').css('div.story_list').remove
		page.at('div#ui-main-column').css('div.share_tool_print').remove
		scrape_file.puts(page.at('div#ui-main-column').text.strip)
		images = page.at('div#ui-main-column').search('img')
		if !images.nil?
			images.each do |image|
				if image['src'].include?("images.csmonitor.com")
					if page.uri.to_s.include?("https")
						image_source = image['src'].prepend("https:")
					else
						image_source = image['src'].prepend("http:")
					end		
					image_name = "#{@directory}/#{title}_image.jpg"
					download_object(image_name, image_source)
				end	
			end		
		end	
		links_array = []
		links = page.at('div#ui-main-column').search('a')
		if !links.empty?
			links.each do |link|
				if !link['href'].nil?
					unless link['href'] == "#"
						links_array << link['href']
					end
				end		
			end
		end	
		article_links_file = File.new("#{@directory}/#{title}_referenced_links.txt","w")
		article_links_file.puts(links_array.to_s)	
	end

	def scrape_twc(page)
		title = "#{page.title}".delete("|,.:").gsub(" ", "-")
		scrape_file = File.new("#{@directory}/#{title}.txt","w")
		page.at('section#article-content').css('script').remove
		page.at('section#article-content').css('div.main-right-rail').remove
		scrape_file.puts(page.at('section#article-content').text.strip)	
	end

	def scrape_workers_org(page)
		title = "#{page.title}".delete("|,.:").gsub(" ", "-")
		scrape_file = File.new("#{@directory}/#{title}.txt","w")
		page.at('article.type-post').css('div.sharedaddy').remove
		scrape_file.puts(page.at('article.type-post').text.strip)
		images = page.at('article.type-post').search('img')
		article_img = 0
		if !images.empty?
			images.each do |image|
				article_img += 1
				image_source = image['src']
				image_name = "#{@directory}/#{title}_image#{article_img}.jpg"
				download_object(image_name, image_source)
			end	
		end		
	end

	def get_opensource_comments(comments, title)
		comments_array = []
		comments.each do |comment|
			comments_array << comment
		end
		opensource_comments_csv = "#{@new_directory}/#{title}_comments.csv"
		CSV.open(opensource_comments_csv, 'ab') do |csv|
			file = CSV.read(opensource_comments_csv,:encoding => "iso-8859-1",:col_sep => ",")
			if file.none?
				csv << ["replier", "reply_to", "date", "comment", "upvotes", "downvotes"]
			end
			comments_array.each_with_index do |comment, i|
				if comment.parent.attributes.first[1].value == "indented"
					reply_to = comments_array[i-1].css('img').first.attributes['title'].value
				else
					reply_to = ""
				end		
				csv << [comment.css('img').first.attributes['title'].value, reply_to, comment.css('span[property="dc:date dc:created"]').first.attributes['content'].value, comment.css('div.field-name-comment-body').text.strip, comment.css('span.up-current-score').text.strip, comment.css('span.down-current-score').text.strip]
			end	
		end	
	end		

	def scrape_opensource_com(page)
		title = "#{page.title}".delete("|,.:").gsub(" ", "-")
		scrape_file = File.new("#{@new_directory}/#{title}.txt","w")
		get_opensource_comments(page.at('div.pane-node-comments').css('div.comment'), title)
		page.at('div#main').css('div.os-article__sidebar').remove
		page.at('div#main').css('span.byline__social').remove
		page.at('div#main').css('div.authorbio').remove
		page.at('div#main').css('h1#page-title').remove
		page.at('div#main').css('div.pane-node-field-default-license').remove
		page.at('div#main').css('div.pane-node-field-tags').remove
		page.at('div#main').css('div.view-related-content-callout').remove
		page.at('div#main').css('div.field-name-field-file-image-caption').remove
		page.at('div#main').css('div.os-article__content-below').remove
		page.at('div#main').css('div.pane-os-article-contributions').remove
		scrape_file.puts(page.at('div#main').text.strip)
		images = page.at('div#main').search('img')
		article_img = 0
		if !images.empty?
			images.each do |image|
				article_img += 1
				image_source = image['src']
				image_name = "#{@new_directory}/#{title}_image#{article_img}.jpg"
				download_object(image_name, image_source)
			end	
		end	
		links_array = []
		links = page.at('div#main').search('a')
		if !links.empty?
			links.each do |link|
				if !link['href'].nil?
					if link['href'].include?("http")
						links_array << link['href']
					end
				end
			end
		end	
		iframes = page.at('div#main').search('iframe')
		if !iframes.empty?
			iframes.each do |iframe|
				links_array << iframe.attributes['src'].value
			end
		end	
		article_links_file = File.new("#{@new_directory}/#{title}_referenced_links.txt","w")
		article_links_file.puts(links_array.to_s)	
	end

	def create_opensource_csv(page)
		os_csv = "#{ARGV.last}/opensource_articles.csv"
		CSV.open(os_csv, 'ab') do |csv|
			file = CSV.read(os_csv,:encoding => "iso-8859-1",:col_sep => ",")
			if file.none?
				csv << ["title", "author", "create_date", "body"]
			end
			csv << [page.at('div.pane-node-title').text.strip, page.at('.byline__author').text.strip, Date.parse(page.at('.byline__date').text.strip.gsub("Posted ", "")), page.at('div.os-article__content').text.strip]
  		end
	end

	def scrape_hewlett(page)
		title = "#{page.title}".delete("|,.:").gsub(" ", "-")
		scrape_file = File.new("#{@new_directory}/#{title}.txt","w")
		page.at('main.main').css('script').remove
		page.at('main.main').css('h4').remove
		page.at('main.main').css('div.share').remove
		page.at('main.main').css('ul.tag-list').remove
		page.at('main.main').css('div.related-stories-row').remove
		scrape_file.puts(page.at('main.main').text.strip)
		images = page.at('main.main').search('img')
		article_img = 0
		if !images.empty?
			images.each do |image|
				article_img += 1
				image_source = image['src']
				image_name = "#{@new_directory}/#{title}_image#{article_img}.jpg"
				download_object(image_name, image_source)
			end	
		end	
		links_array = []
		links = page.at('main.main').search('a')
		if !links.empty?
			links.each do |link|
				if !link['href'].nil?
					if link['href'].include?("http")
						links_array << link['href']
					end
				end
			end
		end	
		iframes = page.at('main.main').search('iframe')
		if !iframes.empty?
			iframes.each do |iframe|
				links_array << iframe.attributes['src'].value
			end
		end	
		article_links_file = File.new("#{@new_directory}/#{title}_referenced_links.txt","w")
		article_links_file.puts(links_array.to_s)	
	end

	def create_hewlett_csv(page)
		hewlett_csv = "#{ARGV.last}/hewlett_articles.csv"
		CSV.open(hewlett_csv, 'ab') do |csv|
			file = CSV.read(hewlett_csv,:encoding => "iso-8859-1",:col_sep => ",")
			if file.none?
				csv << ["title", "author", "create_date", "body"]
			end	
			csv << [page.at('h1.entry-title').text.strip, page.at('cite').text.strip.gsub("By ", ""), Date.parse(page.at('time').text.strip), page.at('div.wysiwyg').text.strip]
  		end
	end

	def scrape_edsurge(page)
		title = "#{page.title}".delete("|,.:").gsub(" ", "-")
		scrape_file = File.new("#{@new_directory}/#{title}.txt","w")
		page.at('article').css('div[itemprop="publisher"]').remove
		page.at('article').css('h4').remove
		page.at('article').css('div.mt2.mb2').remove
		page.at('article').css('p:last-child').remove
		page.at('article').css('.tag.roboto').remove
		page.at('article').css('.btn-comments').remove
		page.at('article').css('.caption').remove
		scrape_file.puts(page.at('article').text.strip)
		images = page.at('article').search('img')
		article_img = 0
		if !images.empty?
			images.each do |image|
				article_img += 1
				image_source = image['src']
				image_name = "#{@new_directory}/#{title}_image#{article_img}.jpg"
				download_object(image_name, image_source)
			end	
		end	
		links_array = []
		links = page.at('article').search('a')
		if !links.empty?
			links.each do |link|
				if !link['href'].nil?
					if link['href'].include?("http")
						links_array << link['href']
					end
				end
			end
		end	
		iframes = page.at('article').search('iframe')
		if !iframes.empty?
			iframes.each do |iframe|
				links_array << iframe.attributes['src'].value
			end
		end	
		article_links_file = File.new("#{@new_directory}/#{title}_referenced_links.txt","w")
		article_links_file.puts(links_array.to_s)	
	end

	def create_edsurge_csv(page)
		es_csv = "#{ARGV.last}/edsurge_articles.csv"
		CSV.open(es_csv, 'ab') do |csv|
			file = CSV.read(es_csv,:encoding => "iso-8859-1",:col_sep => ",")
			if file.none?
				csv << ["title", "author", "create_date", "body"]
			end
			csv << [page.at('h1').text.strip, page.at('.byline > a').text.strip, Date.parse(page.at('.published-date').text.strip), page.at('div.article').text.strip]
  		end
	end

	def scrape_creativecommons(page)
		title = "#{page.title}".delete("|,.:").gsub(" ", "-")
		scrape_file = File.new("#{@new_directory}/#{title}.txt","w")
		page.at('article').css('div.post-category').remove
		page.at('article').css('div.post-tags').remove
		page.at('article').css('.sharedaddy').remove
		scrape_file.puts(page.at('article').text.strip)
		images = page.at('article').search('img')
		article_img = 0
		if !images.empty?
			images.each do |image|
				article_img += 1
				image_source = image['src']
				image_name = "#{@new_directory}/#{title}_image#{article_img}.jpg"
				download_object(image_name, image_source)
			end	
		end	
		links_array = []
		links = page.at('article').search('a')
		if !links.empty?
			links.each do |link|
				if !link['href'].nil?
					if link['href'].include?("http")
						links_array << link['href']
					end
				end
			end
		end	
		iframes = page.at('article').search('iframe')
		if !iframes.empty?
			iframes.each do |iframe|
				links_array << iframe.attributes['src'].value
			end
		end	
		article_links_file = File.new("#{@new_directory}/#{title}_referenced_links.txt","w")
		article_links_file.puts(links_array.to_s)	
	end

	def create_creativecommons_csv(page)
		cc_csv = "#{ARGV.last}/creativecommons_articles.csv"
		CSV.open(cc_csv, 'ab') do |csv|
			file = CSV.read(cc_csv,:encoding => "iso-8859-1",:col_sep => ",")
			if file.none?
				csv << ["title", "author", "create_date", "body"]
			end
			csv << [page.at('h1.entry-title').text.strip, page.at('div.author-name').text.strip, Date.parse(page.at('div.author-date').text.strip), page.search('div.entry-content > p').text.strip]
  		end
	end

	def scrape_newyorktimes(page)
		title = "#{page.title}".delete("|,.:").gsub(" ", "-")
		scrape_file = File.new("#{@new_directory}/#{title}.txt","w")
		page.at('article').css('.byline-column').remove
		page.at('article').css('.supported-by').remove
		page.at('article').css('.kicker').remove
		page.at('article').css('div.story-meta-footer-sharetools').remove
		page.at('article').css('script').remove
		page.at('article').css('div.story-notes').remove
		page.at('article').css('.skip-to-text-link').remove
		page.at('article').css('.feedback-prompt').remove
		page.at('article').css('div[data-attribute-type="Related"]').remove
		page.at('article').css('div.ad').remove
		page.at('article').css('ul.footer').remove
		page.at('article').css('div.footer-tags').remove
		page.at('article').css('form').remove
		page.at('article').css('div.messages').remove
		page.at('article').css('.story-print-citation').remove
		scrape_file.puts(page.at('article').text.strip)
		images = page.at('article').search('img')
		article_img = 0
		if !images.empty?
			images.each do |image|
				article_img += 1
				image_source = image['src']
				image_name = "#{@new_directory}/#{title}_image#{article_img}.jpg"
				download_object(image_name, image_source)
			end	
		end	
		links_array = []
		links = page.at('article').search('a')
		if !links.empty?
			links.each do |link|
				if !link['href'].nil?
					if link['href'].include?("http")
						links_array << link['href']
					end
				end
			end
		end	
		iframes = page.at('article').search('iframe')
		if !iframes.empty?
			iframes.each do |iframe|
				links_array << iframe.attributes['src'].value
			end
		end	
		article_links_file = File.new("#{@new_directory}/#{title}_referenced_links.txt","w")
		article_links_file.puts(links_array.to_s)	
	end

	def create_newyorktimes_csv(page)
		nyt_csv = "#{ARGV.last}/newyorktimes_articles.csv"
		CSV.open(nyt_csv, 'ab') do |csv|
			file = CSV.read(nyt_csv,:encoding => "iso-8859-1",:col_sep => ",")
			if file.none?
				csv << ["title", "author", "create_date", "body"]
			end
			if !page.at('.headline').nil?
				csv << [page.at('.headline').text.strip, page.at('.byline-author').text.strip, Date.parse(page.at('time').text.strip), page.search('.story-body-text').text.strip]
			else		
				csv << [page.at('.entry-title').text.strip, page.at('.fn').text.strip, Date.parse(page.at('time').text.strip), page.search('.story-body-text').text.strip]
			end	
  		end
	end

	def scrape_openknowledge(page)
		title = "#{page.title}".delete("|,.:").gsub(" ", "-")
		scrape_file = File.new("#{@new_directory}/#{title}.txt","w")
		page.at('div.main').css('div#comments').remove
		page.at('div.main').css('div.sharedaddy').remove
		page.at('div.main').css("p:contains('Other posts') + ul").remove
		page.at('div.main').css("p:contains('Other posts')").remove
		page.at('div.main').css('div#jp-relatedposts').remove
		page.at('div.main').css('footer.entry-footer').remove
		page.at('div.main').css("p:contains('guest post is')").remove
		scrape_file.puts(page.at('div.main').text.strip)
		images = page.at('div.main').search('img')
		article_img = 0
		if !images.empty?
			images.each do |image|
				article_img += 1
				image_source = image['src']
				image_name = "#{@new_directory}/#{title}_image#{article_img}.jpg"
				download_object(image_name, image_source)
			end	
		end	
		links_array = []
		links = page.at('div.main').search('a')
		if !links.empty?
			links.each do |link|
				if !link['href'].nil?
					if link['href'].include?("http")
						links_array << link['href']
					end
				end
			end
		end	
		iframes = page.at('div.main').search('iframe')
		if !iframes.empty?
			iframes.each do |iframe|
				links_array << iframe.attributes['src'].value
			end
		end	
		article_links_file = File.new("#{@new_directory}/#{title}_referenced_links.txt","w")
		article_links_file.puts(links_array.to_s)	
	end

	def create_openknowledge_csv(page)
		ok_csv = "#{ARGV.last}/openknowledge_articles.csv"
		CSV.open(ok_csv, 'ab') do |csv|
			file = CSV.read(ok_csv,:encoding => "iso-8859-1",:col_sep => ",")
			if file.none?
				csv << ["title", "author", "create_date", "body"]
			end
			csv << [page.at('div.container > h1').text.strip, page.at('.post__meta > a').text.strip, Date.parse(page.at('.post__meta').text.strip.gsub(/, by [a-zA-Z]*/, "")), page.at('div.entry-content').text.strip]
  		end
	end

	def scrape_hybridpedagogy(page)
		title = "#{page.title}".delete("|,.:").gsub(" ", "-")
		scrape_file = File.new("#{@new_directory}/#{title}.txt","w")
		page.at('article').css('.fa-comments-o').remove
		page.at('article').css('.gdlr-single-blog-tag').remove
		scrape_file.puts(page.at('article').text.strip)
		images = page.at('article').search('img')
		article_img = 0
		if !images.empty?
			images.each do |image|
				article_img += 1
				image_source = image['src']
				image_name = "#{@new_directory}/#{title}_image#{article_img}.jpg"
				download_object(image_name, image_source)
			end	
		end	
		links_array = []
		links = page.at('article').search('a')
		if !links.empty?
			links.each do |link|
				if !link['href'].nil?
					if link['href'].include?("http")
						links_array << link['href']
					end
				end
			end
		end	
		iframes = page.at('article').search('iframe')
		if !iframes.empty?
			iframes.each do |iframe|
				links_array << iframe.attributes['src'].value
			end
		end	
		article_links_file = File.new("#{@new_directory}/#{title}_referenced_links.txt","w")
		article_links_file.puts(links_array.to_s)	
	end

	def create_hybridpedagogy_csv(page)
		hp_csv = "#{ARGV.last}/hybridpedagogy_articles.csv"
		CSV.open(hp_csv, 'ab') do |csv|
			file = CSV.read(hp_csv,:encoding => "iso-8859-1",:col_sep => ",")
			if file.none?
				csv << ["title", "author", "create_date", "body"]
			end
			csv << [page.at('.gdlr-blog-title').text.strip, page.at('div.blog-author').text.strip.gsub("Written by ", ""), Date.parse(page.at('div.gdlr-blog-date-wrapper').text.strip), page.at('div.gdlr-blog-content').text.strip]
  		end
	end

###TODO: Try the Medium API
	def scrape_medium_com(page)
		title = "#{page.title}".delete("|,.:").gsub(" ", "-")
		scrape_file = File.new("#{@new_directory}/#{title}.txt","w")
		#TODO: Get comments
		#get_medium_comments(page.at('div.pane-node-comments').css('div.comment'), title)
		scrape_file.puts(page.at('div.section-content').text.strip)
		images = page.at('div.section-content').search('img')
		article_img = 0
		if !images.empty?
			images.each do |image|
				article_img += 1
				image_source = image['src']
				image_name = "#{@new_directory}/#{title}_image#{article_img}.jpg"
				download_object(image_name, image_source)
			end	
		end	
		links_array = []
		links = page.at('div.section-content').search('a')
		if !links.empty?
			links.each do |link|
				if !link['href'].nil?
					if link['href'].include?("http")
						links_array << link['href']
					end
				end
			end
		end	
		iframes = page.at('div.section-content').search('iframe')
		if !iframes.empty?
			iframes.each do |iframe|
				link_url = "https://medium.com#{iframe.attributes['src'].value}"
				links_array << link_url
			end
		end	
		article_links_file = File.new("#{@new_directory}/#{title}_referenced_links.txt","w")
		article_links_file.puts(links_array.to_s)	
	end

	def create_medium_csv(page)
		medium_csv = "#{ARGV.last}/medium_articles.csv"
		CSV.open(medium_csv, 'ab') do |csv|
			file = CSV.read(medium_csv,:encoding => "iso-8859-1",:col_sep => ",")
			if file.none?
				csv << ["title", "author", "create_date", "body"]
			end
			csv << [page.at('.graf--title').text.strip, page.at('.u-flex0 > a >img').attributes['alt'].value.gsub("Go to the profile of ", ""), Date.parse(page.at('.postMetaInline > time').text.strip), page.at('div.section-content').text.strip]
  		end
	end

	def scrape_mic(page)
		title = "#{page.title}".delete("|,.:").gsub(" ", "-")
		scrape_file = File.new("#{@directory}/#{title}.txt","w")
		page.at('div.main-container.article-page').css('style').remove
		page.at('div.main-container.article-page').css('div.share-media').remove
		page.at('div.main-container.article-page').css('div.fb-like-container').remove
		page.at('div.main-container.article-page').css('div.article-author').remove
		page.at('div.main-container.article-page').css('div.by-line > a > img').remove
		scrape_file.puts(page.at('div.main-container.article-page').text.strip)
		if !page.at('img#hero-image-element').nil?
			header = page.at('img#hero-image-element')
			image_source = header['src']
			image_name = "#{@directory}/#{title}_image_header.jpg"
			download_object(image_name, image_source)
		end	
		images = page.at('div.main-container.article-page').search('img')
		article_img = 0
		if !images.empty?
			images.each do |image|
				article_img += 1
				image_source = image['src']
				image_name = "#{@directory}/#{title}_image#{article_img}.jpg"
				download_object(image_name, image_source)
			end	
		end		
		links_array = []
		links = page.at('div.main-container.article-page').search('a')
		if !links.empty?
			links.each do |link|
				if link['href'].include?("http")
					links_array << link['href']
				end
			end
		end	
		article_links_file = File.new("#{@directory}/#{title}_referenced_links.txt","w")
		article_links_file.puts(links_array.to_s)
	end

	def scrape_huffingtonpost(page)
		title = "#{page.title}".delete("|,.:").gsub(" ", "-")
		scrape_file = File.new("#{@new_directory}/#{title}.txt","w")
		page.at('article.entry').css('script').remove
		page.at('article.entry').css('span.entry-eyebrow').remove
		page.at('article.entry').css('div.follow-author').remove
		page.at('article.entry').css('div.tag-cloud').remove
		page.at('article.entry').css('div.below-entry__comments').remove
		page.at('article.entry').css('ul.follow-us__networks').remove
		page.at('article.entry').css('div.follow-us').remove
		page.at('article.entry').css('div.follow-us-snapchat-overlay').remove
		page.at('article.entry').css('.below-entry-recirc__conversations-header').remove
		page.at('article.entry').css('.timestamp__date--modified').remove
		page.at('article.entry').css('div.contributor-disclaimer').remove
		page.at('article.entry').css('div.books').remove
		page.at('article.entry').css('.image__caption').remove
		scrape_file.puts(page.at('article.entry').text.strip)
		links_array = []
		links = page.at('article.entry').search('a')
		if !links.empty?
			links.each do |link|
				if !link['href'].nil? && link['href'].include?("http")
					links_array << link['href']
				end	
			end
		end	
		article_links_file = File.new("#{@new_directory}/#{title}_referenced_links.txt","w")
		article_links_file.puts(links_array.to_s)
		get_facebook_comments(page.uri.to_s)	
	end

	def create_huffingtonpost_csv(page)
		huffingtonpost_csv = "#{ARGV.last}/huffingtonpost_articles.csv"
		CSV.open(huffingtonpost_csv, 'ab') do |csv|
			file = CSV.read(huffingtonpost_csv,:encoding => "iso-8859-1",:col_sep => ",")
			if file.none?
				csv << ["title", "author", "create_date", "body"]
			end
			csv << [page.at('.headline__title').text.strip, page.at('.author-card__details').text.strip.gsub("By ", ""), Date.strptime(page.at('.timestamp__date--published').text.strip.split(" ")[0].gsub("/", "-"),'%m-%d-%Y'), page.at('div.entry__text').text.strip]
  		end
	end

	def scrape_foxnews(page)
		title = "#{page.title}".delete("|,.:").gsub(" ", "-")
		scrape_file = File.new("#{@directory}/#{title}.txt","w")
		page.at('article').css('h2 > a').remove
		page.at('article').css("a:contains('Associated Press')")
		page.at('article').css('div.social-count').remove
		scrape_file.puts(page.at('article').text.strip)
	end

	def scrape_atlantablackstar(page)
		title = "#{page.title}".delete("|,.:").gsub(" ", "-")
		scrape_file = File.new("#{@directory}/#{title}.txt","w")
		page.at('article').css('ul.td-category').remove
		page.at('article').css('div.td-post-sharing').remove
		page.at('article').css('script').remove
		page.at('article').css('figcaption.wp-caption-text').remove
		page.at('article').css('div.td-post-source-tags').remove
		page.at('article').css('div.td-post-next-prev').remove
		page.at('article').css('div.td-author-name').remove
		page.at('article').css('div.td-post-comments').remove
		page.at('article').css('div.td-post-views').remove
		scrape_file.puts(page.at('article').text.strip)
		images = page.at('article').search('img')
		article_img = 0
		if !images.nil?
			images.each do |image|
				article_img += 1 
				image_source = image['src']
				image_name = "#{@directory}/#{title}_image#{article_img}.jpg"
				download_object(image_name, image_source)
			end	
		end		
		links_array = []
		links = page.at('article').search('a')
		if !links.empty?
			links.each do |link|
				links_array << link.attributes['href'].value
			end
		end	
		article_links_file = File.new("#{@directory}/#{title}_referenced_links.txt","w")
		article_links_file.puts(links_array.to_s)
		get_facebook_comments(page.uri.to_s)	
	end

	def scrape_bet(page)
		title = "#{page.title}".delete("|,.:").gsub(" ", "-")
		scrape_file = File.new("#{@directory}/#{title}.txt","w")
		page.at('div.page__body').css('script').remove
		page.at('div.page__body').css('div.taglinks').remove
		page.at('div.page__body').css('p.page__main__timestamp').remove
		page.at('div.page__body').css('p.image-source-cnt').remove
		page.at('div.page__body').css('h3.comments__header').remove
		scrape_file.puts(page.at('div.page__body').text.strip)
		image = page.at('div.hero__img-wrapper>img')
		article_img = 0
		if !image.nil?
			article_img += 1 
			image_source = image['src']
			image_name = "#{@directory}/#{title}_image#{article_img}.jpg"
			download_object(image_name, image_source)
		end		
		links_array = []
		links = page.at('div.bodycopy').search('a')
		if !links.empty?
			links.each do |link|
				links_array << link.attributes['href'].value
			end
		end	
		iframe = page.at('div.embedded_html__content>iframe')
		if !iframe.nil?
			links_array << iframe['src']
		end	
		article_links_file = File.new("#{@directory}/#{title}_referenced_links.txt","w")
		article_links_file.puts(links_array.to_s)
		get_facebook_comments(page.uri.to_s)	
	end

	def scrape_gawker(page)
		title = "#{page.title}".delete("|,.:").gsub(" ", "-")
		scrape_file = File.new("#{@directory}/#{title}.txt","w")
		page.at('div.post').css('style').remove
		page.at('div.post').css('div.meta__views').remove
		page.at('div.post').css('div.tags-container').remove
		page.at('div.post').css('div.meta__avatar').remove
		page.at('div.post').css('figcaption').remove
		scrape_file.puts(page.at('div.post').text.strip)
		images = page.at('div.post').search('img')
		article_img = 0
		if !images.empty?
			images.each do |image|
				article_img += 1
				image_source = image['src'].prepend("http:")
				puts image_source
				puts '++++++++++++++++++'
				image_name = "#{@directory}/#{title}_image#{article_img}.jpg"
				download_object(image_name, image_source)
			end	
		end		
		links_array = []
		links = page.at('div.post').search('a')
		if !links.empty?
			links.each do |link|
				links_array << link.attributes['href'].value
			end
		end	
		article_links_file = File.new("#{@directory}/#{title}_referenced_links.txt","w")
		article_links_file.puts(links_array.to_s)	
	end

	def scrape_dailytarheel(page)
		title = "#{page.title}".delete("|,.:").gsub(" ", "-")
		scrape_file = File.new("#{@directory}/#{title}.txt","w")
		if !page.at('a[data-disqus-identifier]').nil?
			disqus_id = page.at('a[data-disqus-identifier]').attributes['data-disqus-identifier'].value
		else
			disqus_id = ""
		end
		page.at('article.copy-container').css('script').remove
		page.at('article.copy-container').css('div.related-stories-right').remove
		page.at('article.copy-container').css('div.mug').remove
		scrape_file.puts(page.at('article.copy-container').text.strip)
		images = page.at('article.copy-container').search('img')
		article_img = 0
		if !images.empty?
			images.each do |image|
				article_img += 1
				if !image['src'].empty?
					image_source = image['src']
					image_name = "#{@directory}/#{title}_image#{article_img}.jpg"
					download_object(image_name, image_source)
				end	
			end	
		end		
		links_array = []
		links = page.at('article.copy-container').search('a')
		if !links.empty?
			links.each do |link|
				links_array << link.attributes['href'].value
			end
		end	
		article_links_file = File.new("#{@directory}/#{title}_referenced_links.txt","w")
		article_links_file.puts(links_array.to_s)	
		get_dailytarheel_comments(disqus_id, page.uri.to_s)
	end

	def scrape_independent(page)
		title = "#{page.title}".delete("|,.:").gsub(" ", "-")
		scrape_file = File.new("#{@directory}/#{title}.txt","w")
		page.at('article.full-article').css('srcipt').remove
		page.at('article.full-article').css('ol.breadcrumbs').remove
		page.at('article.full-article').css('div.fb-info').remove
		page.at('article.full-article').css('div.inline-block').remove
		page.at('article.full-article').css('div.full-gallery').remove
		page.at('article.full-article').css('div.grid-mod-gallery').remove
		page.at('article.full-article').css('div.relatedlinkslist').remove
		page.at('article.full-article').css('ul.inline-pipes-list').remove
		page.at('article.full-article').css('a.syndication-btn').remove
		page.at('article.full-article').css('div.box-comments').remove
		page.at('article.full-article').css('div.sidebar').remove
		scrape_file.puts(page.at('article.full-article').text.strip)
		images = page.at('article.full-article').search('img')
		article_img = 0
		if !images.empty?
			images.each do |image|
				article_img += 1
				image_source = image['src']
				image_name = "#{@directory}/#{title}_image#{article_img}.jpg"
				download_object(image_name, image_source)
			end	
		end
		links_array = []
		links = page.at('article.full-article').search('a')
		if !links.empty?
			links.each do |link|
				links_array << link.attributes['href'].value
			end
		end	
		article_links_file = File.new("#{@directory}/#{title}_referenced_links.txt","w")
		article_links_file.puts(links_array.to_s)	
	end

	def scrape_colorlines(page)
		title = "#{page.title}".delete("|,.:").gsub(" ", "-")
		scrape_file = File.new("#{@directory}/#{title}.txt","w")
		page.at('div.main-container').css('nav[role="navigation"]').remove
		page.at('div.main-container').css('div.social-media').remove
		page.at('div.main-container').css('div.donate').remove
		page.at('div.main-container').css('div.subscribe').remove
		page.at('div.main-container').css('div.search-link').remove
		page.at('div.main-container').css('section#block-views-ongoing-topics-block').remove
		page.at('div.main-container').css('section#block-cl-share-cl-share').remove
		page.at('div.main-container').css('ul.links').remove
		page.at('div.main-container').css('div.comment-wrapper').remove
		page.at('div.main-container').css('section#block-apachesolr-search-mlt-002').remove
		page.at('div.main-container').css('div.view-content').remove
		page.at('div.main-container').css('div.article-tags').remove
		scrape_file.puts(page.at('div.main-container').text.strip)
		images = page.at('div.main-container').search('img')
		article_img = 0
		if !images.empty?
			images.each do |image|
				article_img += 1
				image_source = image['src']
				image_name = "#{@directory}/#{title}_image#{article_img}.jpg"
				download_object(image_name, image_source)
			end	
		end
		links_array = []
		links = page.at('div.main-container').search('a[href]')
		if !links.empty?
			links.each do |link|
				links_array << link.attributes['href'].value
			end
		end	
		article_links_file = File.new("#{@directory}/#{title}_referenced_links.txt","w")
		article_links_file.puts(links_array.to_s)	
	end

	def scrape_indy(page)
		title = "#{page.title}".delete("|,.:").gsub(" ", "-").strip
		scrape_file = File.new("#{@directory}/#{title}.txt","w")
		page.at('div#storyBody').css('span.clicktozoom').remove
		page.at('div#storyBody').css('li.imageCredit').remove
		header = page.at('div#StoryHeader').text.strip
		body = page.at('div#storyBody').text.strip
		scrape_file.puts(header + "\n" + body)
		images = page.at('div#storyBody').search('img')
		article_img = 0
		if !images.empty?
			images.each do |image|
				article_img += 1
				image_source = image['src']
				image_name = "#{@directory}/#{title}_image#{article_img}.jpg"
				download_object(image_name, image_source)
			end	
		end		
		links_array = []
		links = page.at('div#storyBody').search('a')
		if !links.empty?
			links.each do |link|
				links_array << link['href']
			end
		end	
		article_links_file = File.new("#{@directory}/#{title}_referenced_links.txt","w")
		article_links_file.puts(links_array.to_s)	
	end

	def scrape_newsone(page)
		title = "#{page.title}".delete("|,.:").gsub(" ", "-").strip
		scrape_file = File.new("#{@directory}/#{title}.txt","w")
		page.at('div[class="post"]').css('script').remove
		page.at('div[class="post"]').css('div.post-meta__category').remove
		page.at('div[class="post"]').css('span.trending-label').remove
		page.at('div[class="post"]').css('div.post-breadcrumbs').remove
		page.at('div[class="post"]').css('div.post-sharing').remove
		page.at('div[class="post"]').css('span.read-counter-container').remove
		page.at('div[class="post"]').at("p:contains('SOURCE:')").remove
		page.at('div[class="post"]').at("p:contains('SEE ALSO:')").remove
		page.at('div[class="post"]').css('div.post-meta__tags').remove
		page.at('div[class="post"]').css('div.author-more-tab').remove
		page.at('div[class="post"]').css('div.post-content__pulled-left').remove
		page.at('div[class="post"]').css('div[class="ione-gallery__images"]').remove
		page.at('div[class="post"]').css('div.post-comments').remove
		page.at('div[class="post"]').css('div[class="module-container politicker"]').remove
		page.at('div[class="post"]').css('div.ione-widget-trending').remove
		page.at('div[class="post"]').css('div.top-ten').remove
		page.at('div[class="post"]').css('div.module-more-link').remove
		related_links = page.at('div[class="post"]').css("p/strong/a/@href:contains('https://newsone.com')")
		related_links.each do |rl|
			page.at('div[class="post"]').css("a[href=\"#{rl.value}\"]").remove
		end	
		scrape_file.puts(page.at('div[class="post"]').text.strip)
		images = page.at('div[class="post"]').search('img')
		links_array = []
		media = page.at('div[class="post"]').search('img')[1]
		image_source = media['data-lazy-src']
		image_name = "#{@directory}/#{title}_image.jpg"
		download_object(image_name, image_source)
		links_array << "https://social.newsinc.com/media/json/#{media['ndn-tracking-group']}/#{media['ndn-config-video-id']}/singleVideoOG.html?type=VideoPlayer/Single&widgetId=2&trackingGroup=#{media['ndn-tracking-group']}&videoId=#{media['ndn-config-video-id']}"	
		links = page.at('div[class="post"]').search('a')
		if !links.empty?
			links.each do |link|
				links_array << link['href']
			end
		end	
		article_links_file = File.new("#{@directory}/#{title}_referenced_links.txt","w")
		article_links_file.puts(links_array.to_s)	
	end

	def scrape_time(page)
		title = "#{page.title}".delete("|,.:").gsub(" ", "-")
		scrape_file = File.new("#{@directory}/#{title}.txt","w")
		page.at('div[data-reactid="170"]').css('span[data-reactid="189"]').remove
		page.at('div[data-reactid="170"]').css('span[data-reactid="196"]').remove
		scrape_file.puts(page.at('div[data-reactid="170"]').text.strip)
		images = page.at('div[data-reactid="170"]').search('img')
		article_img = 0
		if !images.empty?
			images.each do |image|
				article_img += 1
				image_source = image['src']
				image_name = "#{@directory}/#{title}_image#{article_img}.jpg"
				download_object(image_name, image_source)
			end	
		end		
		links_array = []
		links = page.at('div[data-reactid="170"]').search('a')
		if !links.empty?
			links.each do |link|
				if !link['href'].nil?
					if !link['href'].include?("#")
						links_array << link['href']
					end
				end		
			end
		end	
		article_links_file = File.new("#{@directory}/#{title}_referenced_links.txt","w")
		article_links_file.puts(links_array.to_s)	
	end

	def scrape_chronicle_higher_ed(page)
		title = "#{page.title}".delete("|,.:").gsub(" ", "-")
		scrape_file = File.new("#{@directory}/#{title}.txt","w")
		page.at('article.content-item__container--article').css('span.content-item__tone').remove
		scrape_file.puts(page.at('article.content-item__container--article').text.strip)
		images = page.at('article.content-item__container--article').search('img')
		article_img = 0
		if !images.empty?
			images.each do |image|
				article_img += 1
				image_source = image['src']
				image_name = "#{@directory}/#{title}_image#{article_img}.jpg"
				download_object(image_name, image_source)
			end	
		end		
		links_array = []
		links = page.at('article.content-item__container--article').search('a[href]')
		if !links.empty?
			links.each do |link|
				links_array << link.attributes['href'].value
			end
		end	
		article_links_file = File.new("#{@directory}/#{title}_referenced_links.txt","w")
		article_links_file.puts(links_array.to_s)	
	end

	def scrape_dailywire(page)
		title = "#{page.title}".delete("|,.:").gsub(" ", "-")
		scrape_file = File.new("#{@directory}/#{title}.txt","w")
		if !page.at('a[data-disqus-identifier]').nil?
			disqus_id = page.at('a[data-disqus-identifier]').attributes['data-disqus-identifier'].value
		else
			disqus_id = ""
		end
		page.at('section#main').css('script').remove
		page.at('section#main').css('div.field-tags').remove
		page.at('section#main').css('div.next-article').remove
		page.at('section#main').css('div#in-article-related-content').remove
		page.at('section#main').css('div#article-plugs').remove
		page.at('section#main').css('div#block-dailywire-parsely-hotwire').remove
		page.at('section#main').css('div.article-teaser-template').remove
		page.at('section#main').css('button#article-teasers-load-more').remove
		page.at('section#main').css('div.fbshare-article-closer').remove
		page.at('section#main').css('div.block-disqus').remove
		scrape_file.puts(page.at('section#main').text.strip)
		images = page.at('section#main').search('img')
		article_img = 0
		if !images.empty?
			images.each do |image|
				article_img += 1
				image_source = image['src']
				image_name = "#{@directory}/#{title}_image#{article_img}.jpg"
				download_object(image_name, image_source)
			end	
		end
		links_array = []
		links = page.at('section#main').search('a[href]')
		if !links.empty?
			links.each do |link|
				if !link['href'].nil? || !link['href'].include?("search/site?")
					unless link['href'] == "#"
						links_array << link['href']
					end
				end		
			end
		end	
		article_links_file = File.new("#{@directory}/#{title}_referenced_links.txt","w")
		article_links_file.puts(links_array.to_s)
		get_dailywire_comments(disqus_id, page.uri.to_s)	
	end

	def scrape_insidehighered(page)
		title = "#{page.title}".delete("|,.:").gsub(" ", "-")
		scrape_file = File.new("#{@directory}/#{title}.txt","w")
		if !page.at('a[data-disqus-identifier]').nil?
			disqus_id = page.at('a[data-disqus-identifier]').attributes['data-disqus-identifier'].value
		else
			disqus_id = ""
		end
		page.at('div[id="block-system-main"]').css('script').remove
		page.at('div[id="block-system-main"]').css('div.pane-topics').remove
		page.at('div[id="block-system-main"]').css('div[id="breadcrumbs"]').remove
		page.at('div[id="block-system-main"]').css('div.views-field-disqus-comment-count').remove
		page.at('div[id="block-system-main"]').css('div.read-more-by').remove
		page.at('div[id="block-system-main"]').css('div.jump-to-comments-lower').remove
		page.at('div[id="block-system-main"]').css('div.article-foot-dnu').remove
		page.at('div[id="block-system-main"]').css('div.panel-col-last').remove
		page.at('div[id="block-system-main"]').css('div.panel-col-middle').remove
		page.at('div[id="block-system-main"]').css('div[id="comments-here"]').remove
		page.at('div[id="block-system-main"]').css('div.pane-disqus').remove
		page.at('div[id="block-system-main"]').css('div.pane-apachesolr-search').remove
		page.at('div[id="block-system-main"]').css('div.recent-articles-below-story').remove
		page.at('div[id="block-system-main"]').css('div.quicktakes-below-story').remove
		page.at('div[id="block-system-main"]').css('div.article-foot-apps').remove
		page.at('div[id="block-system-main"]').css('div.article-foot-printshare').remove
		page.at('div[id="block-system-main"]').css('div.recent-blogs-below-story').remove
		scrape_file.puts(page.at('div[id="block-system-main"]').text.strip)
		images = page.at('div[id="block-system-main"]').search('img')
		article_img = 0
		if !images.empty?
			images.each do |image|
				article_img += 1
				image_source = image['src']
				image_name = "#{@directory}/#{title}_image#{article_img}.jpg"
				download_object(image_name, image_source)
			end	
		end
		links_array = []
		links = page.at('div[id="block-system-main"]').search('a[href]')
		if !links.empty?
			links.each do |link|
				links_array << link.attributes['href'].value
			end
		end	
		article_links_file = File.new("#{@directory}/#{title}_referenced_links.txt","w")
		article_links_file.puts(links_array.to_s)
		get_insidehighered_comments(disqus_id, page.uri.to_s)	
	end

	def scrape_usatoday_college(page)
		title = "#{page.title}".delete("|,.:").gsub(" ", "-")
		scrape_file = File.new("#{@directory}/#{title}.txt","w")
		if !page.at('div.comments-expanded').nil?
			disqus_id = page.at('div.comments-expanded').text.split("disqus_identifier =")[1].split(";")[0].gsub("\"", "").strip
			puts disqus_id
		else
			disqus_id = ""
		end
		page.at('div.entry-content').css('div.sharedaddy').remove
		page.at('div.entry-content').css('div.related-posts-wrap').remove
		page.at('div.entry-content').css('p.advertisement-label').remove
		page.at('div.entry-content').css('div.single-related').remove
		page.at('div.entry-content').css('div.story-share-buttons').remove
		page.at('div.entry-content').css('p.post-tags').remove
		page.at('div.entry-content').css('div.credit').remove
		scrape_file.puts(page.at('div.entry-content').text.strip)
		images = page.at('div.entry-content').search('img')
		article_img = 0
		if !images.empty?
			images.each do |image|
				article_img += 1
				image_source = image['src']
				image_name = "#{@directory}/#{title}_image#{article_img}.jpg"
				download_object(image_name, image_source)
			end	
		end
		links_array = []
		links = page.at('div.entry-content').search('a')
		if !links.empty?
			links.each do |link|
				links_array << link.attributes['href'].value
			end
		end	
		iframes = page.at('div.entry-content').search('iframe')
		if !iframes.empty?
			iframes.each do |iframe|
				links_array << iframe.attributes['src'].value
			end
		end	
		article_links_file = File.new("#{@directory}/#{title}_referenced_links.txt","w")
		article_links_file.puts(links_array.to_s)
		get_facebook_comments(page.uri.to_s)
	end


	def scrape_washingtontimes(page)
		title = "#{page.title}".delete("|,.:").gsub(" ", "-")
		scrape_file = File.new("#{@directory}/#{title}.txt","w")
		if !page.at('div.article-text').nil?
			disqus_id = page.at('div.article-text').css('script').text.split("disqus_identifier =")[1].split(";")[0].strip
			puts disqus_id
		else
			disqus_id = ""
		end
		page.at('div.article-text').css('script').remove
		page.at('div.article-text').css('div.share-and-comments').remove
		page.at('div.article-text').css('a.dsq-brlink').remove
		page.at('div.article-text').css('noscript').remove
		page.at('div.article-text').css('div.permission').remove
		page.at('div.article-text').css('p.expand').remove
		page.at('div.article-text').css('p.contract.hide').remove
		page.at('div.article-text').css("p:contains('can be reached at')").remove
		scrape_file.puts(page.at('div.article-text').text.strip)
		images = page.at('div.article-text').search('img')
		article_img = 0
		if !images.empty?
			images.each do |image|
				article_img += 1
				image_source = image['src']
				image_name = "#{@directory}/#{title}_image#{article_img}.jpg"
				download_object(image_name, image_source)
			end	
		end
		links_array = []
		links = page.at('div.article-text').search('a')
		if !links.empty?
			links.each do |link|
				links_array << link['href']
			end
		end	
		article_links_file = File.new("#{@directory}/#{title}_referenced_links.txt","w")
		article_links_file.puts(links_array.to_s)
		get_washingtontimes_comments(disqus_id, page.uri.to_s)	
	end



	def scrape_wncn(page)
		title = "#{page.title}".delete("|,.:").gsub(" ", "-")
		scrape_file = File.new("#{@directory}/#{title}.txt","w")
		if !page.at('div.comments-expanded').nil?
			disqus_id = page.at('div.comments-expanded').text.split("disqus_identifier =")[1].split(";")[0].gsub("\"", "").strip
			puts disqus_id
		else
			disqus_id = ""
		end
		page.at('div.entry-content').css('div.sharedaddy').remove
		page.at('div.entry-content').css('div.related-posts-wrap').remove
		page.at('div.entry-content').css('p.advertisement-label').remove
		scrape_file.puts(page.at('div.entry-content').text.strip)
		images = page.at('div.entry-content').search('img')
		article_img = 0
		if !images.empty?
			images.each do |image|
				article_img += 1
				image_source = image['src']
				image_name = "#{@directory}/#{title}_image#{article_img}.jpg"
				download_object(image_name, image_source)
			end	
		end
		links_array = []
		links = page.at('div.entry-content').search('a')
		if !links.empty?
			links.each do |link|
				links_array << link.attributes['href'].value
			end
		end	
		iframes = page.at('div.entry-content').search('iframe')
		if !iframes.empty?
			iframes.each do |iframe|
				links_array << iframe.attributes['src'].value
			end
		end	
		article_links_file = File.new("#{@directory}/#{title}_referenced_links.txt","w")
		article_links_file.puts(links_array.to_s)
		get_wncn_comments(disqus_id, page.uri.to_s)	
	end

	def scrape_wordpress(page)
		title = "#{page.title}".delete("|,.:").gsub(" ", "-")
		scrape_file = File.new("#{@directory}/#{title}.txt","w")
		page.at('div.entry-content').css('div.sharedaddy').remove
		scrape_file.puts(page.at('div.entry-content').text.strip)
		images = page.at('div.entry-content').search('img')
		article_img = 0
		if !images.empty?
			images.each do |image|
				article_img += 1
				image_source = image['src']
				image_name = "#{@directory}/#{title}_image#{article_img}.jpg"
				download_object(image_name, image_source)
			end	
		end
		links_array = []
		links = page.at('div.entry-content').search('a')
		if !links.empty?
			links.each do |link|
				links_array << link.attributes['href'].value
			end
		end	
		iframes = page.at('div.entry-content').search('iframe')
		if !iframes.empty?
			iframes.each do |iframe|
				links_array << iframe.attributes['src'].value
			end
		end	
		article_links_file = File.new("#{@directory}/#{title}_referenced_links.txt","w")
		article_links_file.puts(links_array.to_s)	
	end

	def scrape_abc11(page)
		title = "#{page.title}".delete("|,.:").gsub(" ", "-")
		scrape_file = File.new("#{@directory}/#{title}.txt","w")
		if !page.at('div.comments-expanded').nil?
			disqus_id = page.at('div.comments-expanded').text.split("disqus_identifier =")[1].split(";")[0].gsub("\"", "").strip
			puts disqus_id
		else
			disqus_id = ""
		end
		links_array = []
		videos = page.css('textarea[class="textarea"]')
		videos.each do |video|
			if !video.children.first.text.empty?
				vid = video.children.first.text.split(" ")[3].split("src=").last.delete("\"")
			else
				vid = video.children.first['src']
			end
			links_array << vid
		end			
		page.at('div.content').css('div.taxonomy').remove
		page.at('div.content').css('div.share-panel').remove
		page.at('div.content').css('div.share-panel-new').remove
		page.at('div.content').css('div[error="noflash"]').remove
		page.at('div.content').css('span.wtvd').remove
		page.at('div.content').css('a[href="http://bit.ly/1TfmsxL"]').remove
		page.at('div.content').css('div.story-taxonomy').remove
		page.at('div.content').css('section.comments').remove
		page.at('div.content').css('section.related').remove
		page.at('div.content').css('section.topic').remove
		page.at('div.content').css('section.top-stories').remove
		page.at('div.content').css('section.top-video').remove
		page.at('div.content').css('div.embed-code').remove
		page.at('div.content').css('a.embed-btn').remove
		page.at('div.content').css('a.button.button-block').remove
		scrape_file.puts(page.at('div.content').text.strip)
		images = page.search('div.video-poster')
		article_img = 0
		if !images.empty?
			images.each do |image|
				if !image['data-imgsrc'].nil?
					article_img += 1
					image_source = image['data-imgsrc'].gsub(".jpg", "") + "_630x354.jpg"
					image_name = "#{@directory}/#{title}_image#{article_img}.jpg"
					download_object(image_name, image_source)
				end	
			end	
		end
		images2 = page.at('div.content').search('img')
		body_img = 0
		if !images2.empty?
			images2.each do |img|
				if !img['src'].nil?
					if !img['src'].include?("likeusfb")
						body_img += 1
						img_source = img['src']
						img_name = "#{@subdirectory}/#{title}_image#{article_img}.jpg"
						download_object(img_name, img_source)
					end	
				end	
			end	
		end
		images3 = page.search('div.image')
		if !images3.empty?
			images3.each do |i|
				if !i['data-imgsrc'].nil?
					article_img += 1
					i_source = i['data-imgsrc'].gsub(".jpg", "") + "_630x354.jpg"
					i_name = "#{@directory}/#{title}_image#{article_img}.jpg"
					download_object(i_name, i_source)
				end	
			end	
		end
		links = page.at('div.content').search('a')
		if !links.empty?
			links.each do |link|
				links_array << link.attributes['href'].value
			end
		end	
		article_links_file = File.new("#{@directory}/#{title}_referenced_links.txt","w")
		article_links_file.puts(links_array.to_s)
		get_abc11_comments(disqus_id, page.uri.to_s)	
	end

	def scrape_wral(page)
		title = "#{page.title}".delete("|,.:").gsub(" ", "-")
		scrape_file = File.new("#{@directory}/#{title}.txt","w")
		if !page.at('a.darklink').nil?
			comments_page = page.at('a.darklink').attributes['href'].value
		else
			comments_page = page.at('a.icon-ico-comment').attributes['href'].value
		end	
		comments_link = "http://www.wral.com/#{comments_page}"
		get_wral_comments(comments_link, title)
		page.at('div.l-default-body').css('div[hidden]').remove
		page.at('div.l-default-body').css('script').remove
		page.at('div.l-default-body').css('ul.utility-list').remove
		page.at('div.l-default-body').css('div.story-credits').remove
		page.at('div.l-default-body').css('div.h-6').remove
		page.at('div.l-default-body').css('div#share_email_modal').remove
		page.at('div.l-default-body').css('h2.h-6').remove
		page.at('div.l-default-body').css('div.box').remove
		page.at('div.l-default-body').css('div.taso-block').remove
		scrape_file.puts(page.at('div.l-default-body').text.strip)
		images = page.at('div.l-default-body').search('img')
		article_img = 0
		if !images.empty?
			images.each do |image|
				article_img += 1
				if !image['src'].nil?
					image_source = image['src']
					image_name = "#{@directory}/#{title}_image#{article_img}.jpg"
					download_object(image_name, image_source)
				end	
			end	
		end
		links_array = []
		links = page.at('div.l-default-body').search('a')
		if !links.empty?
			links.each do |link|
				links_array << link.attributes['href'].value
			end
		end	
		iframes = page.at('div.l-default-body').search('iframe')
		if !iframes.empty?
			iframes.each do |iframe|
				links_array << iframe.attributes['src'].value
			end
		end	
		article_links_file = File.new("#{@directory}/#{title}_referenced_links.txt","w")
		article_links_file.puts(links_array.to_s)	
	end

	def scrape_guardian(page)
		title = "#{page.title}".delete("|,.:").gsub(" ", "-")
		scrape_file = File.new("#{@directory}/#{title}.txt","w")
		if !page.at('a[data-link-name="View all comments"]').nil?
			comment_page = page.at('a[data-link-name="View all comments"]')
			comments_link = comment_page['href']
			get_guardian_comments(comments_link, title)
		end	
		page.at('article').css('div.content__section-label').remove
		page.at('article').css('ul.social').remove
		page.at('article').css('div.old-article-message').remove
		page.at('article').css('div.rich-link').remove
		page.at('article').css('div.submeta').remove
		scrape_file.puts(page.at('article').text.strip)
		images = page.at('article').search('img')
		article_img = 0
		if !images.empty?
			images.each do |image|
				article_img += 1
				if !image['src'].nil?
					image_source = image['src']
					image_name = "#{@directory}/#{title}_image#{article_img}.jpg"
					download_object(image_name, image_source)
				end	
			end	
		end
		links_array = []
		links = page.at('article').search('a')
		if !links.empty?
			links.each do |link|
				if link['href'].include?("http")
					links_array << link['href']
				end	
			end
		end	
		article_links_file = File.new("#{@directory}/#{title}_referenced_links.txt","w")
		article_links_file.puts(links_array.to_s)	
	end

	def get_wral_comments(comments_link, title)
		comment_array = []
		comments_page = @mechanize.get(comments_link)
		comments_page.css('div.l-default-body > ul > li').each do |li|
			comment_array << li
		end
		wral_comments_csv = "#{@directory}/#{title}_comments.csv"
		CSV.open(wral_comments_csv, 'ab') do |csv|
			file = CSV.read(wral_comments_csv,:encoding => "iso-8859-1",:col_sep => ",")
			if file.none?
				csv << ["name", "date", "comment", "reply_to"]
			end
			comment_array.each do |comment|
				if !comment.children[6].children[3].nil?
					csv << [comment.children[1].children.children[0].text, comment.children[1].children.children[1].text, comment.children[7].children.text.strip ,comment.children[6].children.text.gsub("View quoted thread", "").strip]
				else
					csv << [comment.children[1].children.children[0].text, comment.children[1].children.children[1].text, comment.children[5].text.strip ,""]
				end	
			end	
		end	
	end	

	def get_guardian_comments(comments_link, title)
		comment_array = []
		comments_page = call_mechanize(comments_link)
		puts comments_page.title
		puts '++++++++++++'
		comments_page.css('div.d-comment__inner--top-level').each do |comment|
			comment_array << comment
		end
		page_number = 2
		while !comments_page.title.include?("500")
			puts comments_page.title
			comments_page = call_mechanize("#{comments_link}?page=#{page_number}")
			comments_page.css('div.d-comment__inner--top-level').each do |comment|
				comment_array << comment
			end
			page_number +=1	
		end
		guardian_comments_csv = "#{@directory}/#{title}_comments.csv"
		CSV.open(guardian_comments_csv, 'ab') do |csv|
			file = CSV.read(guardian_comments_csv,:encoding => "iso-8859-1",:col_sep => ",")
			if file.none?
				csv << ["replier", "reply_to", "date", "comment", "upvotes"]
			end
			comment_array.each do |comment|
				if !comment.children[1].children[3].children[5].nil?
					csv << [comment.children[1].children[3].children[1].children.children.text.strip, comment.children[1].children[3].children[5].children.children.text.strip, comment.children[1].children[3].children[7].children.children.text.strip, comment.children[3].children[3].children.children[1].children.text.strip, comment.children[3].children[1]['data-recommend-count'].to_i]
				else
					csv << [comment.children[1].children[3].children[1].children.children.text.strip, "", comment.children[1].children[3].children[3].children[1].children[1].children.text.strip, comment.children[3].children[3].children.children[1].children.text.strip ,comment.children[3].children[1]['data-recommend-count'].to_i]
				end	
			end	
		end	
	end	
	
	def scrape_chronicle(page)
		title = "#{page.title}".delete("|,").gsub(" ", "-")
		scrape_file = File.new("#{@directory}/#{title}.txt","w")
		if !page.at('a[data-disqus-identifier]').nil?
			disqus_id = page.at('a[data-disqus-identifier]').attributes['data-disqus-identifier'].value
		else
			disqus_id = ""
		end		
		page.at('article.main').css('script').remove
		page.at('article.main').css('div.recommended-stories').remove
		page.at('article.main').css('ul.share-boxes').remove
		page.at('article.main').css('div.subscribe-share').remove
		page.at('article.main').css('div.comments').remove
		scrape_file.puts(page.at('article.main').text.strip)
		images = page.at('article.main').search('img')
		article_img = 0
		if !images.empty?
			images.each do |image|
				article_img += 1
				image_source = image['src']
				image_name = "#{@directory}/#{title}_image#{article_img}.jpg"
				download_object(image_name, image_source)
			end	
		end	
		links_array = []
		links = page.at('article.main').search('a')
		if !links.empty?
			links.each do |link|
				links_array << link.attributes['href'].value
			end
		end	
		iframes = page.at('article.main').search('iframe')
		if !iframes.empty?
			iframes.each do |iframe|
				links_array << iframe.attributes['src'].value
			end
		end	
		article_links_file = File.new("#{@directory}/#{title}_referenced_links.txt","w")
		article_links_file.puts(links_array.to_s)	
		get_chronicle_comments(disqus_id, page.uri.to_s)
	end	

	def scrape_no(page)
		title = "#{page.title}".delete("|,").gsub(" ", "-")
		scrape_file = File.new("#{@directory}/#{title}.txt","w")
		links_array = []
		if !page.at('div#related-links').text.blank?
			if !page.at('div#related-links').children[1].nil?
				video = page.at('div#related-links').children[1].children[1].children[1].children[1]['href']
				links_array << video
			end
		end		
		page.at('section.container.story').css('script').remove
		page.at('section.container.story').css('div.gallery-counter').remove
		page.at('section.container.story').css('ul.share-icons').remove
		page.at('section.container.story').css('div.more-stories-link').remove
		page.at('section.container.story').css('div.narrow-rail').remove
		page.at('section.container.story').css('div.story-related').remove
		page.at('section.container.story').css('div.caption-toggle').remove
		page.at('section.container.story').css('.heading').remove
		page.at('section.container.story').css('div.video-media').remove
		scrape_file.puts(page.at('section.container.story').text.strip)
		images = page.at('section.container.story').search('//span[@data-width-1140]')
		article_img = 0
		if !images.empty?
			images.each do |image|
				article_img += 1
				image_source = image.attributes['data-src'].value
				image_name = "#{@directory}/#{title}_image#{article_img}.jpg"
				download_object(image_name, image_source)
			end	
		end	
		links = page.at('section.container.story').search('a')
		if !links.empty?
			links.each do |link|
				links_array << link.attributes['href'].value
			end
		end	
		iframes = page.at('section.container.story').search('iframe')
		if !iframes.empty?
			iframes.each do |iframe|
				links_array << iframe.attributes['src'].value
			end
		end	
		article_links_file = File.new("#{@directory}/#{title}_referenced_links.txt","w")
		article_links_file.puts(links_array.to_s)
		get_facebook_comments(page.uri.to_s)	
	end	

	def scrape_technician(page)
		title = "#{page.title}".delete("|,.:").gsub(" ", "-")
		scrape_file = File.new("#{@directory}/#{title}.txt","w")
		scrape_file.puts(page.at('div[itemprop = "articleBody"]').text.strip)
		images = page.search('div[itemprop = "image"]')
		article_img = 0
		if !images.empty?
			images.each do |image|
				article_img += 1
				image_source = image.children[5]['data-src']
				image_name = "#{@directory}/#{title}_image#{article_img}.jpg"
				download_object(image_name, image_source)
			end	
		end	
		get_facebook_comments(page.uri.to_s)	
	end

	def scrape_herald_sun(page)
		title = "#{page.title}".delete("|,.:").gsub(" ", "-")
		@scrape_file = File.new("#{@directory}/#{title}.txt","w")
		if !page.uri.to_s.include?("/multimedia/photo_gallery/")
			title = "#{page.title}".delete("|,.:").gsub(" ", "-")
			page.at('article.article-default').css('script').remove
			page.at('article.article-default').css('div.asset-masthead').remove
			page.at('article.article-default').css('ul.list-inline').remove
			page.at('article.article-default').css('a.buy-now').remove
			page.at('article.article-default').css('div.asset-tagline').remove
			page.at('article.article-default').css('div.asset-tags').remove
			page.at('article.article-default').css('div.asset-author').remove
			page.at('article.article-default').css('section.block').remove
			page.at('article.article-default').css('style').remove
			page.at('article.article-default').css('a.twitter-timeline').remove
			page.at('article.article-default').css('span.expand').remove
			@scrape_file.puts(page.at('article.article-default').text.strip)
			images = page.at('article.article-default').search('img')
			article_img = 0
			if !images.empty?
				images.each do |image|
					article_img += 1
					if !image.attributes['src'].nil?
						@image_source = image.attributes['src'].value
					else
						@image_source = image.attributes['data-src'].value
					end	
					image_name = "#{@directory}/#{title}_image#{article_img}.jpg"	
					download_object(image_name, @image_source)
				end	
			end
		else
			article_img = 0
			page.css('div[itemprop="image"]').each do |image|
				article_img += 1
				@image_source = image.children[5]['data-src']
				image_name = "#{@directory}/#{title}_image#{article_img}.jpg"	
				download_object(image_name, @image_source)	
			end
			paragraphs = []
			page.css('div.caption-text > p').each do |paragraph|
				if !paragraphs.include?(paragraph.text)
					paragraphs << paragraph.text
					File.open(@scrape_file, "a+") { |f| f.puts(paragraph.text + "\n")}
				end
			end		
		end					
	end

	def scrape_washingtonpost(page)
		title = "#{page.title}".delete("|,.:").gsub(" ", "-")
		scrape_file = File.new("#{@directory}/#{title}.txt","w")
		page.at('div.article-body').css('span.pb-tool.email').remove
		page.at('div.article-body').css('script').remove
		page.at('div.article-body').css('span.tweet-authors').remove
		page.at('div.article-body').at('span.pb-byline').remove
		scrape_file.puts(page.at('div.article-body').text.strip)
		images = page.at('div.article-body').search('img')
		article_img = 0
		if !images.empty?
			images.each do |image|
				if !image['src'].nil?
					article_img += 1
					image_source = image['src']
					image_name = "#{@directory}/#{title}_image#{article_img}.jpg"
					download_object(image_name, image_source)
				end	
			end	
		end	
		links_array = []
		links = page.at('div.article-body').search('a')
		if !links.empty?
			links.each do |link|
				if !link['href'].nil?
					links_array << link['href']
				end
			end	
		end	
		article_links_file = File.new("#{@directory}/#{title}_referenced_links.txt","w")
		article_links_file.puts(links_array.to_s)	
	end	

	def get_comment_plugin(id, title)
		@fb_comments = []
		@fbcomments = @graph.get_connection(id, 'comments')
		if !@fbcomments.empty?
			while !@fbcomments.nil?
				@fb_comments << @fbcomments
				@fbcomments = @fbcomments.next_page
			end
			if !@fb_comments.nil?
				create_facebook_comments_csv(@fb_comments, title)
			end	
		end	
	end

	def get_fb_object_comments_data(comment)
		created = DateTime.parse(comment['created_time'])
	  	@comment_create_date = created.strftime("%m-%d-%Y")
	  	@comment_create_time = created.strftime("%H:%M:%S")
		@comment_id = comment['id']
		@comment_message = comment['message']
		#@comment_me_translation = translate_message(@comment_message)
		@comment_author = comment['from']['name']
		#@comment_au_translation = translate_message(@comment_author)
		@comment_author_id = comment['from']['id']
		@comment_likes = comment['like_count']
		@author_likes_object = comment['user_likes']
	end	

	def create_facebook_object_csv
		file_directory = "#{ARGV.last}/facebook_#{@object_id}"
		check_directory_exists(file_directory)
		object_comments_csv = "#{file_directory}/object_#{@object_id}_and_comments.csv"
		CSV.open(object_comments_csv, 'ab') do |csv|
			file = CSV.read(object_comments_csv,:encoding => "iso-8859-1",:col_sep => ",")
				if file.none?
					csv << ["object_id", "object_description", "object_author", "object_author_translation", "object_au_category", "object_au_id", "object_create_date", "object_create_time", "object_update_date", "object_update_time", "event_name", "event_date", "event_time", "event_venue", "event_location", "location_geocoords", "comment_id", "comment_message", "comment_create_date", "comment_create_time", "comment_author", "comment_author_id", "comment_likes", "author_likes_object"]
					csv << [@object_id, @object_description, @object_author, @object_au_category, @object_au_id, @object_create_date, @object_create_time, @object_update_date, @object_update_time, @event_name, @event_date, @event_time, @event_location, @event_address, @address_geocoordinates]
				end
				@all_comments.each do |comment|
					comment.each do |c|
						get_fb_object_comments_data(c)
						csv << ["", "", "", "", "", "", "", "", "", "", "", @comment_id, @comment_message, @comment_me_translation, @comment_create_date, @comment_create_time, @comment_author, @comment_author_id, @comment_likes, @author_likes_object]
					end
				end
	  	end
	end

	def get_chronicle_comments(disqus_id, link)
		thread = DisqusApi.v3.threads.list(forum: 'dukechronicle', thread: "link:#{link}", include:["open", "closed"]).response
		unless thread.count == 1
			puts disqus_id
			thread = DisqusApi.v3.threads.list(forum: 'dukechronicle', thread: "ident:#{disqus_id}", include: [ "open", "closed" ]).response
		end	
		story_comments = DisqusApi.v3.posts.list(thread: thread.first['id'], limit: 100).response	
		if !story_comments.empty?
			title = thread.first['title'].strip
			create_disqus_comments_csv(story_comments, title)
		end	
	end	

	def get_abc11_comments(disqus_id, link)
		thread = DisqusApi.v3.threads.list(forum: 'abcwtvd', thread: "link:#{link}", include:["open", "closed"]).response
		unless thread.count == 1
			puts disqus_id
			thread = DisqusApi.v3.threads.list(forum: 'abcwtvd', thread: "ident:#{disqus_id}", include: [ "open", "closed" ]).response
		end	
		story_comments = DisqusApi.v3.posts.list(thread: thread.first['id'], limit: 100).response
		if !story_comments.empty?
			title = thread.first['title'].strip
			create_disqus_comments_csv(story_comments, title)
		end	
	end	

	def get_insidehighered_comments(disqus_id, link)
		thread = DisqusApi.v3.threads.list(forum: 'insidehighered', thread: "link:#{link}", include:["open", "closed"]).response
		unless thread.count == 1
			puts disqus_id
			thread = DisqusApi.v3.threads.list(forum: 'insidehighered', thread: "ident:#{disqus_id}", include: [ "open", "closed" ]).response
		end	
		story_comments = DisqusApi.v3.posts.list(thread: thread.first['id'], limit: 100).response
		if !story_comments.empty?
			title = thread.first['title'].strip
			create_disqus_comments_csv(story_comments, title)
		end	
	end	

	def get_dailywire_comments(disqus_id, link)
		thread = DisqusApi.v3.threads.list(forum: 'thedailywire', thread: "link:#{link}", include:["open", "closed"]).response
		unless thread.count == 1
			puts disqus_id
			thread = DisqusApi.v3.threads.list(forum: 'thedailywire', thread: "ident:#{disqus_id}", include: [ "open", "closed" ]).response
		end	
		story_comments = DisqusApi.v3.posts.list(thread: thread.first['id'], limit: 100).response
		if !story_comments.empty?
			title = thread.first['title'].strip
			create_disqus_comments_csv(story_comments, title)
		end	
	end	

	def get_dailytarheel_comments(disqus_id, link)
		thread = DisqusApi.v3.threads.list(forum: 'dailytarheel', thread: "link:#{link}", include:["open", "closed"]).response
		unless thread.count == 1
			puts disqus_id
			thread = DisqusApi.v3.threads.list(forum: 'dailytarheel', thread: "ident:#{disqus_id}", include: [ "open", "closed" ]).response
		end
		story_comments = DisqusApi.v3.posts.list(thread: thread.first['id'], limit: 100).response
		if !story_comments.empty?
			title = thread.first['title'].strip
			create_disqus_comments_csv(story_comments, title)
		end	
	end	

	def get_wncn_comments(disqus_id, link)
		thread = DisqusApi.v3.threads.list(forum: 'wncn', thread: "link:#{link}", include:["open", "closed"]).response
		unless thread.count == 1
			puts disqus_id
			thread = DisqusApi.v3.threads.list(forum: 'wncn', thread: "ident:#{disqus_id}", include: [ "open", "closed" ]).response
		end
		story_comments = DisqusApi.v3.posts.list(thread: thread.first['id'], limit: 100).response
		if !story_comments.empty?
			title = thread.first['title'].strip
			create_disqus_comments_csv(story_comments, title)
		end	
	end	

	def get_washingtontimes_comments(disqus_id, link)
		thread = DisqusApi.v3.threads.list(forum: 'washtimes', thread: "link:#{link}", include:["open", "closed"]).response
		unless thread.count == 1
			puts disqus_id
			thread = DisqusApi.v3.threads.list(forum: 'washtimes', thread: "ident:#{disqus_id}", include: [ "open", "closed" ]).response
		end
		story_comments = DisqusApi.v3.posts.list(thread: thread.first['id'], limit: 100).response
		if !story_comments.empty?
			title = thread.first['title'].strip
			create_disqus_comments_csv(story_comments, title)
		end	
	end	

	def get_facebook_comments(link)
		url = "https://graph.facebook.com/v2.8/?id=#{link}&access_token=#{ARGV[0]}"
		comment_plugin = JSON.parse(open(url).read)
		id = comment_plugin['og_object']['id']
		puts id
		@shares = comment_plugin['share']['share_count'] 
		title = link.split("/").last
		get_comment_plugin(id, title)
	end	

end

article = ArticleScraper.new
article.initiate_fb_client
article.initiate_webshot
article.initiate_mechanize
article.initiate_disqus
article.scrape_article(ARGV[1])
