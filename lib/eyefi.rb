$LOAD_PATH.unshift File.expand_path(File.join(File.dirname(__FILE__), ".."))

require 'digest/md5'
require 'lib/archive'
require 'stringio'
require 'exifr'

module Exceptions
  class IntegrityError < StandardError; end
  class IncompleteMetadataError < StandardError; end
end

class EyefiCard
  
  attr_reader :upload_key
  attr_reader :mac_address
  
  def initialize(mac_address, upload_key)
    @mac_address, @upload_key, @photos = mac_address, upload_key, {}
  end
  
  def receive_photo(temp_file, integrity_digest, meta = nil)
    unless meta.nil?
      received_photo = Photo.new(self, temp_file, integrity_digest, meta)
      @photos[received_photo.orginal_name] = received_photo
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
      @photo_fp = StringIO.new(extract_data(@tar_fp))
      update_exif!
    else
      raise Exceptions::IntegrityError
    end
  end
  
  def integrity_compromised?(digest)
    tar_bytes = @tar_fp.read # we need this to be a string
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
    File.new(path, 'w+')
    fp << @photo_fp.read
    fp.close
  end
  
  #######
  private
  #######
  
  def update_exif!
    @exif = EXIFR::JPEG.new(@photo_fp).exif
  end
  
  def extract_data(fp)
    components = []
    tar = Archive::Tar::Reader.new(fp)
    tar.each_entry{|entry|
      components << entry.extract_data!
    }
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