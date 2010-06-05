$LOAD_PATH.unshift File.expand_path(File.join(File.dirname(__FILE__), ".."))

require 'lib/ryfi'
require 'lib/eyefi'
require 'stringio'
require 'exifr'

# Register as many cards as you wish (accepts the card's MAC + upload key)
EyefiCard.register('782201658100', '2c3eadb135e2bd6cff25115ff51ee4c8')

class MyApp < RyfiApp
  
  handle_photos_with :handle_photo
  
  def handle_photo(card, photo)
    EyefiCard.log.debug "Received new photo (#{photo.original_name}) shot with an #{photo.exif[:model]}."
    photo.save_with_original_name! '/Users/kkeiter/Desktop/test'
  end
  
end

# Server must be run on 59278 so that the card can reach it.
MyApp.run! :host => 'localhost', :port => 59278