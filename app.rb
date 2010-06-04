$LOAD_PATH.unshift File.expand_path(File.join(File.dirname(__FILE__), ".."))

require 'lib/ryfi'
require 'lib/eyefi'
require 'stringio'
require 'exifr'

class MyApp < RyfiApp
  
  authorize_cards :find_card
  handle_photos_with :handle_photo
  
  def find_card(mac)
    {'001856102287' => EyefiCard.new('001856102287', '2c3eadb135e2bd6cff25115ff51ee4c8')}[mac]
  end
  
  def handle_photo(card, photo)
    puts "New photo from: #{photo.exif[:model]}"
    photo.save_with_original_name! '/Users/kkeiter/Desktop/test'
  end
  
end

MyApp.run! :host => 'localhost', :port => 59278