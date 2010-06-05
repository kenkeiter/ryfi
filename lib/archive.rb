#!/usr/pkg/bin/ruby -w
#  Copyright 2002 Thomas Hurst <freaky@aagh.net>, All Rights Reserved

module Archive

	module Tar
		BLOCKSIZE = 512

		# Exceptions {{{
		class Error < StandardError
			# Base exception class
		end

		class BadHeaderError < Error
			# Bad header, can be retried in a pinch
		end

		class LengthError < BadHeaderError
			# Field size too small
			def initialize(size)
				@message = "Name too big to fit in header (max #{size})"
			end
		end
		# }}}


		class Reader # {{{
			include Enumerable

			@fp = nil

			def initialize(filehandle)
				@fp = filehandle
			end

			def close()

			end

			def each_entry()
				while entry = next_entry()
					yield(entry)
				end
			end

			def each()
				while entry = next_entry()
					yield(entry)
				end
			end

			# Reads at one record and returns an associated Entry object
			def next_entry()
				buf = @fp.read(BLOCKSIZE)
				if buf == "\000" * BLOCKSIZE
					entry = nil
				else
					entry = Entry.new(buf, @fp)
				end
				entry
			end

			def extract(target)
				each_entry do |entry|
					entry.extract(target)
				end
			end
		end # }}}

		class Writer # {{{
			@fp = nil

			def initialize(filehandle)
				if (filehandle.instance_of(:String))
					# attempt to open the file
				else
					@fp = filehandle
				end
			end

			def add_entry(entry)

			end

			def close()
			
			end
		end # }}}

		class Header # {{{
			# Header related constants {{{
			# Standard lengths
			NAMELEN    = 100
			MODELEN    = 8
			UIDLEN     = 8
			GIDLEN     = 8
			CHKSUMLEN  = 8
			SIZELEN    = 12
			MAGICLEN   = 8
			MODTIMELEN = 12
			UNAMELEN   = 32
			GNAMELEN   = 32
			DEVLEN     = 8
			# Magic tag for a POSIX and GNU archive
			TMAGIC     = 'ustar'
			GNU_TMAGIC = 'ustar  '

			# File types
			LF_OLDFILE = '\0'
			LF_FILE    = '0'
			LF_LINK    = '1'
			LF_SYMLINK = '2'
			LF_CHAR    = '3'
			LF_BLOCK   = '4'
			LF_DIR     = '5'
			LF_FIFO    = '6'
			LF_CONTIG  = '7'
			# }}}

			# Attributes {{{
			@name     = nil
			@mode     = nil
			@uid      = nil
			@gid      = nil
			@size     = nil
			@mtime    = nil
			@chksum   = nil
			@linkflag = nil
			@linkname = nil
			@magic    = nil
			@uname    = nil
			@gname    = nil
			@devmajor = nil
			@devminor = nil
			@raw      = nil
			# }}}

			def initialize(header = nil)
				parse(header) if header
			end

			# Accessors {{{
			attr_reader(:name, :size, :mtime, :uname, :gname, :mode)
			def name=(name)
				if File.basename(name).size > NAMELEN or File.dirname(name).size > NAMELEN
					raise LengthError.new(NAMELEN)
				end

				@name = name
			end

			def linkname=(name)
				if name.size > NAMELEN
					raise LengthError.new(NAMELEN)
				end

				@name = name
			end

			def uname=(name)
				if name.size > UNAMELEN
					raise LengthError.new(UNAMELEN)
				end
			end

			def gname=(name)
				if name.size > GNAMELEN
					raise LengthError.new(GNAMELEN)
				end
			end
			# }}}

			def parse(header) # Attempt to parse a tar record header at all costs {{{
				if (header.size != BLOCKSIZE)
					raise BadHeaderError, "Warning: Header != BLOCKSIZE, archive malformed."
				end

				types  = ['str', 'oct', 'oct', 'oct', 'oct', 'time', 'oct', 'str',
				          'str', 'str', 'str', 'str', 'oct', 'oct']
				fields = header.unpack('A100 A8 A8 A8 A12 A12 A8 A1 A100 A8 A32 A32 A8 A8')
				converted = []

				begin
					while field = fields.shift
						type = types.shift

						case type
						when 'str'
							converted.push(field)
						when 'oct'
							converted.push(field.oct)
						when 'time'
							converted.push(Time::at(field.oct))
						else
							raise "Danger, Will Robinson, this should never, ever happen."
						end
					end

					(@name, @mode, @uid, @gid, @size, @mtime, @chksum,
					@linkflag, @linkname, @magic, @uname, @gname, @devmajor,
					@devminor) = converted

					@raw = header

				rescue ArgumentError => e
					converted.push(field)
					raise BadHeaderError, "Couldn't determine a real value for a field (#{field})"
				end

				# last minute sanity checks
				# we don't support contiguous files.
				if @linkflag == LF_OLDFILE || @linkflag == LF_CONTIG
					@linkflag = LF_FILE
				end

				if @name[-1] == '/' and @linkflag == LF_FILE
					@linkflag = LF_DIR
				end

				if @linkname[0] == '/'
					puts "Stripping leading directory name from entries"
					@linkname = @linkname[1,-1]
				end

				if @size < 0
					puts "A file size of #{@size} is unlikely, forcing to 0"
					@size = 0
				end

				if @magic != TMAGIC and @magic != GNU_TMAGIC
					raise BadHeaderError, "Magic header value '#{@magic}' is invalid."
				end

				@name = @linkname + '/' + @name if @linkname.size > 0

				check_checksum()
			end
			# }}}

			def check_checksum() # {{{
				header = @raw
				header[148,8] = ' ' * 8
				mysum = header.sum
				
				if mysum != @chksum
					raise BadHeaderError, "Warning: checksum mismatch in header: #{mysum} != #{@chksum}"
				end
			end # }}}

			def dir?()
				(@linkflag == LF_DIR)
			end

			def file?()
				(@linkflag == LF_FILE)
			end

			def link?()
				(@linkflag == LF_LINK || @linkflag == LF_SYMLINK)
			end

			def to_str() # {{{
				# FIXME this code doesn't produce a well formed header, even by our standards
				fields = []
				fields.push(@name)
				fields.push(sprintf("%8o", @mode))
				fields.push(sprintf("%8o", @uid))
				fields.push(sprintf("%8o", @gid))
				fields.push(sprintf("%12o", @size))
				fields.push(sprintf("%12o", @mtime.to_i))
				fields.push(' ' * 8)
				fields.push(@linkflag)
				fields.push(@linkname)
				fields.push(@magic)
				fields.push(@uname)
				fields.push(@gname)
				fields.push(sprintf("%8o", @devmajor))
				fields.push(sprintf("%8o", @devminor))
				@chksum = fields.join.sum
				fields[7] = sprintf("%8o", @chksum)
				fields.pack('a100 a8 a8 a8 a12 a12 a8 a1 a100 a8 a32 a32 a8 a8 x167')
			end # }}}
		end # }}}

		class Entry # {{{
			attr_reader(:header, :data)

			def initialize(header = nil, fp = nil)
				@header = Header.new(header)

				if @header.file?
					size = @header.size

					if size > 0
						@data = fp.read(size)
					end

					# seek to the next record
					rem = size % BLOCKSIZE
					if rem > 0
						fp.read((size - rem + BLOCKSIZE) - size)
					end
				end
			end

			def extract_data! # {{{
				unless @header.dir?
					begin
						return @data
					rescue => e
						puts "Couldn't create file for writing, or something: " + e.message
					end
				end
			end # }}}
		end # }}}
	end

end

