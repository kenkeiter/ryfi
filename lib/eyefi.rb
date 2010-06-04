$LOAD_PATH.unshift File.expand_path(File.join(File.dirname(__FILE__), ".."))

require 'digest/md5'
require 'lib/archive'
require 'stringio'
require 'exifr'
require 'Logger'

Log = Logger.new(STDOUT)
Log.level = Logger::DEBUG

class EyefiCard
  
  attr_reader :upload_key
  
  def initialize(mac, upload_key)
    @mac_address, @upload_key, @photos = mac, upload_key, []
  end
  
  def receive_photo(temp_file, integrity_digest, meta = nil)
    Log.debug "#{self} receiving photo: #{temp_file}.."
    unless meta.nil?
      received_photo = Photo.new(self, temp_file, integrity_digest, meta)
      @photos << received_photo
      return received_photo
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
      raise 'Image TAR checksum invalid.'
    end
  end
  
  def integrity_compromised?(digest)
    tar_bytes = @tar_fp.read # we need this to be a string
    pos, tcp_sums = 0, []
    while tar.length % 512 != 0 do
      tar_bytes << "\x00"
    end
    while pos < tar.length do
      tcp_sums << tcp_checksum(tar_bytes[pos..pos + 511])
      pos += 512
    end
    tcp_sums.concat(@card.upload_key.to_a.pack('H*').unpack('S*'))
    out = Digest::MD5.hexdigest(tcp_sums.pack('S*'))
    return !out.eql?(digest)
  end
  
  def save_with_original_name!(path)
    original_name = @meta.filename.split('.')[0..1].join('.')
    fp = File.new(File.join(path, original_name), 'w+')
    fp << @photo_fp.read
    fp.close
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
    counter, two_byte_sum = 0, 0
    bytes << "\x00" if bytes.length % 2 != 0
    while counter < bytes.length do
      two_byte_sum += bytes[counter..counter + 2].unpack('v')[0]
      counter += 2
    end
    while (two_byte_sum >> 16) != 0 do
      two_byte_sum = (two_byte_sum >> 16) + (two_byte_sum & 0xFFFF)
    end
    return ~two_byte_sum & 0xFFFF
  end
  
end