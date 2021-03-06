require "steam/categorizer/version"
require "steam/vdf"

module Steam
  module Categorizer
    require 'httparty'
    require 'nokogiri'
    require 'json'
    require 'set'

    class GameLibrary

      def initialize(url_name:nil, preferences:'~/.config/steam_categorizer.json', shared_config:nil)
        @unmapped_categories = {}
        @category_map = {}
        @steam_config = {}
        
        @preferences = JSON.parse(File.read(File.expand_path(preferences, __FILE__)))
        @preferences['sharedConfig'] = shared_config if shared_config
        @preferences['sharedConfig'] = File.expand_path(@preferences['sharedConfig'])
        @preferences['urlName'] = url_name if url_name

        html = Nokogiri::HTML(HTTParty.get("https://steamcommunity.com/id/#{@preferences['urlName']}/games/?tab=all"))
        script = html.search('script').find {|script_node| script_node.text().include?('rgGames')}
        @owned_games = JSON.parse(script.text[/\[\{"appid.*\}\]/])
      end

      # Identify publisher defined game categories
      def self.extract_publisher_categories(store_page)
        extracted_categories = Set.new()
        store_page.css("div.game_area_details_specs").css("a.name").each do |category_node|
          next if category_node.text().strip() == 'Downloadable Content'
          extracted_categories.add(category_node.text)
        end

        return extracted_categories
      end

      # Identify community defined game tags
      def self.extract_community_tags(store_page)
        extracted_tags = Set.new()
        tags_script = store_page.search("script").select{ |script_node| script_node.text.include?('InitAppTagModal') }
        unless tags_script.empty?
          steam_tags = JSON.parse(tags_script.first.text[/\[\{.*tagid.*\}\]/])
          steam_tags.each do |steam_tag|
            extracted_tags.add(steam_tag['name'])
          end
        end
        store_page.search("script").each do |script_element|
          next unless script_element.text.include?("InitAppTagModal")
          steam_tags = JSON.parse(script_element.text[/\[\{\".*tagid.*\}\]/])
          steam_tags.each do |steam_tag|
            extracted_tags.add(steam_tag['name'])
          end
        end

        return extracted_tags
      end

      # Lookup store page for each game and compile a hash of tags
      def collect_metadata()
        # Set our age to 25 years old to access store pages for mature rated games
        birthday = (Time.now() - (60*60*24*365*25)).to_i()
        headers = {
          'Cookie'=>"birthtime=#{birthday}; lastagecheckage=#{Time.at(birthday).strftime("%e-%B-%Y")}; mature_content=1"
        }

        # 16 Threads should be sufficient
        @owned_games.each_slice(16) do |games|
          threads = []
          games.each do |game|
            threads.push(Thread.new {
              raw_html = HTTParty.get("http://store.steampowered.com/app/#{game['appid']}/", :headers=>headers)
              store_page = Nokogiri::HTML(raw_html)

              publisher_categories = GameLibrary.extract_publisher_categories(store_page)
              community_tags = GameLibrary.extract_community_tags(store_page)

              app_id = game['appid']
              next if @unmapped_categories.key?(app_id)
              @unmapped_categories[app_id] = {}
              unless publisher_categories.empty?()
                @unmapped_categories[app_id]['publisherCategories'] = [] unless @unmapped_categories.key?('publisherCategories')
                @unmapped_categories[app_id]['publisherCategories'] += publisher_categories.to_a()
              end
              unless community_tags.empty?()
                @unmapped_categories[app_id]['communityTags'] = [] unless @unmapped_categories.key?('communityTags')
                @unmapped_categories[app_id]['communityTags'] += community_tags.to_a()
              end
            })
          end
          threads.each do |thread|
            thread.join()
          end
        end
      end

      # Compile list of category names to be used and assign id values
      def map_categories()
        mapped_categories = Set.new
        @unmapped_categories.each do |app_id, unmapped_categories|
          unmapped_categories.each do |category_type, unmapped_category_names|
            unmapped_category_names.each do |unmapped_category_name|
              next unless @preferences['categoryMaps'][category_type].key?(unmapped_category_name)
              @preferences['categoryMaps'][category_type][unmapped_category_name].each do |category_name|
                mapped_categories.add(category_name)
              end
            end
          end
        end

        # Assign id value in alphabetical order
        mapped_categories.to_a.sort.each do |category_name|
          @category_map[category_name] = "#{@category_map.size}"
        end
      end

      # Generate the "apps" map for the vdf config file
      def generate_steam_config()
        apps = {}
        @unmapped_categories.each do |app_id, unmapped_categories|
          app_categories = {}
          unmapped_categories.each do |category_type, unmapped_category_names|
            unmapped_category_names.each do |unmapped_category_name|
              next unless @preferences['categoryMaps'][category_type].key?(unmapped_category_name)
              @preferences['categoryMaps'][category_type][unmapped_category_name].each do |category_name|
                app_categories[@category_map[category_name]] = category_name
              end
            end
          end
          next if app_categories.empty?()
          apps["#{app_id}"] = { 'tags'=>app_categories }
        end

        # Open the existing steam sharedconfig.vdf file
        steam_config = VDF.parse(File.read(@preferences['sharedConfig']))

        # Delete any existing categories
        steam_config['UserRoamingConfigStore']['Software']['Valve']['Steam']['Apps'].each do |app_id, app_map|
          if app_map.key?("tags")
            steam_config['UserRoamingConfigStore']['Software']['Valve']['Steam']['Apps'][app_id].delete('tags')
            if steam_config['UserRoamingConfigStore']['Software']['Valve']['Steam']['Apps'][app_id].empty?
              steam_config['UserRoamingConfigStore']['Software']['Valve']['Steam']['Apps'].delete(app_id)
            end
          end
        end
        # Merge the newly generated apps map with the old one
        apps.each do |app_id, app_map|
          if steam_config['UserRoamingConfigStore']['Software']['Valve']['Steam']['Apps'].key?(app_id)
            steam_config['UserRoamingConfigStore']['Software']['Valve']['Steam']['Apps'][app_id].merge!(apps[app_id])
          else
            steam_config['UserRoamingConfigStore']['Software']['Valve']['Steam']['Apps'][app_id] = apps[app_id]
          end
        end
        @steam_config = steam_config
      end

      # Save Steam config to file
      def export_steam_config()
        f = File.open(@preferences['sharedConfig'], 'w')
        vdf = VDF.generate(@steam_config)
        f.write(vdf)
      end
    end

  end
end
