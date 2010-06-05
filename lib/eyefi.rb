$LOAD_PATH.unshift File.expand_path(File.join(File.dirname(__FILE__), ".."))

require 'digest/md5'
require 'lib/archive'
require 'stringio'
require 'exifr'
require 'singleton'
require 'logger'

module Exceptions
  class IntegrityError < StandardError; end
  class IncompleteMetadataError < StandardError; end
end

class EyefiCard
  
  include Singleton
  
  @@cards = {}
  @@log = nil
  
  class << self
    
    def find_by_mac(mac)
      @@cards[mac]
    end
    
    def log
      @@log = Logger.new(STDOUT) if @@log.nil?
      @@log.level = Logger::DEBUG
      return @@log
    end
    
    def register(*args)
      inst = EyefiCardInstance.new(*args)
      @@cards[args[0]] = inst unless @@cards.key? args[0]
      return inst
    end
    
  end
  
end

class EyefiCardInstance
  
  attr_reader :upload_key
  attr_reader :mac_address
  attr_reader :photos
  
  def initialize(mac_address, upload_key)
    EyefiCard.log.debug "Instantiating new card: #{mac_address}, #{upload_key}"
    @mac_address, @upload_key, @photos = mac_address, upload_key, {}
  end
  
  def receive_photo(temp_file, integrity_digest, meta = nil)
    unless meta.nil?
      EyefiCard.log.debug "Card #{@mac_address} attempting to receive new photo: #{temp_file}, #{integrity_digest}."
      received_photo = Photo.new(self, temp_file, integrity_digest, meta)
      @photos[received_photo.original_name] = received_photo
      return received_photo
    else
      raise Exceptions::IncompleteMetadataError
    end
  end
  
  def credential(nonce)
    Digest::MD5.hexdigest((@mac_address + nonce + @upload_key).to_a.pack('H*'))
  end
  
end

class Photo
  
  attr_reader :exif
  
  def initialize(card, temp_file, integrity_digest, meta)
    @card, @exif, @meta = card, nil, meta
    @tar_fp = StringIO.new(temp_file.read)
    unless integrity_compromised? integrity_digest
      EyefiCard.log.debug "#{self}: File integrity verified!"
      @photo_fp = StringIO.new(extract_data(@tar_fp))
      update_exif!
    else
      raise Exceptions::IntegrityError
    end
  end
  
  def integrity_compromised?(digest)
    EyefiCard.log.debug "#{self} verifying file integrity against digest: #{digest}"
    
    @tar_fp.rewind; tar_bytes = @tar_fp.read # we need this to be a string
    pos, tcp_sums = 0, []
    while tar_bytes.length % 512 != 0 do
      tar_bytes << "\x00"
    end
    while pos < tar_bytes.length do
      tcp_sums << tcp_checksum(tar_bytes[pos..pos + 511])
      pos += 512
    end
    tcp_sums.concat(@card.upload_key.to_a.pack('H*').unpack('S*'))
    out = Digest::MD5.hexdigest(tcp_sums.pack('S*'))
    return !out.eql?(digest)
  end
  
  def original_name
    @meta.filename.split('.')[0..1].join('.')
  end
  
  def save_with_original_name!(path)
    save! File.join(path, original_name)
  end
  
  def save!(path)
    fp = File.new(path, 'w+')
    @photo_fp.rewind; fp << @photo_fp.read
    fp.close
  end
  
  #######
  private
  #######
  
  def update_exif!
    EyefiCard.log.debug "#{self}'s updating exif."
    @exif = EXIFR::JPEG.new(@photo_fp).exif
  end
  
  def extract_data(fp)
    fp.rewind
    components = []
    tar = Archive::Tar::Reader.new(fp)
    tar.each_entry{|entry|
      components << entry.extract_data!
    }
    EyefiCard.log.debug "#{self} extracted archive (length: #{fp.length})"
    components.first
  end
  
  def tcp_checksum(bytes)
    counter, byte_sum = 0, 0
    bytes << "\x00" if bytes.length % 2 != 0
    while counter < bytes.length do
      byte_sum += bytes[counter..counter + 2].unpack('v')[0]
      counter += 2
    end
    while (byte_sum >> 16) != 0 do
      byte_sum = (byte_sum >> 16) + (byte_sum & 0xFFFF)
    end
    return ~byte_sum & 0xFFFF
  end
  
end