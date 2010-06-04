$LOAD_PATH.unshift File.expand_path(File.join(File.dirname(__FILE__), ".."))

require 'lib/ryfi'
require 'lib/eyefi'
require 'stringio'
require 'exifr'

MyCard = EyefiCard.new('000000000000', 'superSecretUploadKeyInHex')

class MyApp < RyfiApp
  
  authorize_cards :find_card
  handle_photos_with :handle_photo
  
  def find_card(mac)
    {'000000000000' => MyCard}[mac]
  end
  
  def handle_photo(card, photo)
    puts "New photo from: #{photo.exif[:model]}"
    photo.save_with_original_name! '/Path/To/My/Deskop'
  end
  
end

MyApp.run! :host => 'localhost', :port => 59278 # must be on this port for card