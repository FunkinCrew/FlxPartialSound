package;

import haxe.io.Bytes;
import haxe.io.BytesInput;
import haxe.io.Path;
import lime.app.Future;
import lime.app.Promise;
import lime.media.AudioBuffer;
import lime.net.HTTPRequest;
import lime.net.HTTPRequestHeader;

class PartialSoundUtil
{
	/**
	 * returns empty audio buffer on error
	 * @param path 
	 * @param rangeStart what percent of the song should it start at
	 * @param rangeEnd what percent of the song should it end at
	 * @return Future<AudioBuffer>
	 */
	public static function partialLoadFromFile(path:String, ?rangeStart:Float = 0, ?rangeEnd:Float = 1):Future<AudioBuffer>
	{
		#if (html || js)
		var promise:Promise<AudioBuffer> = new Promise<AudioBuffer>();

		requestContentLength(path).onComplete(function(contentLength:Int)
		{
			trace("content length: " + contentLength);
			var startByte:Int = Std.int(contentLength * rangeStart);
			var endByte:Int = Std.int(contentLength * rangeEnd);

			trace("startByte: " + startByte);
			trace("endByte: " + endByte);

			var http = new HTTPRequest<Bytes>(path);
			var rangeHeader:HTTPRequestHeader = new HTTPRequestHeader("Range", 'bytes=$startByte-$endByte');
			http.headers.push(rangeHeader);
			http.load().onComplete(function(data:Bytes)
			{
				trace("incoming data length: " + data.length);
				var audioBuffer:AudioBuffer = new AudioBuffer();
				switch (Path.extension(path))
				{
					case "mp3":
						audioBuffer = parseBytesMp3(data);
					case "ogg":
						promise.error("OGG not supported yet");
					default:
						promise.error("Unsupported file type: " + Path.extension(path));
				}
				promise.complete(audioBuffer);
			});
		});

		return promise.future;
		#elseif sys
		// load from filesystem
		#end
	}

	static function requestContentLength(path:String):Future<Int>
	{
		var promise:Promise<Int> = new Promise<Int>();
		var fileLengthInBytes:Int = 0;
		var httpFileLength = new HTTPRequest<Bytes>(path);
		httpFileLength.headers.push(new HTTPRequestHeader("Accept-Ranges", "bytes"));
		httpFileLength.method = HEAD;
		httpFileLength.enableResponseHeaders = true;

		httpFileLength.load(path).onComplete(function(data:Bytes)
		{
			var contentLengthHeader:HTTPRequestHeader = httpFileLength.responseHeaders.filter(function(header:HTTPRequestHeader)
			{
				return header.name == "content-length";
			})[0];

			promise.complete(Std.parseInt(contentLengthHeader.value));
		});

		return promise.future;
	}

	/**
	 * Parses bytes from a partial mp3 file, and returns an AudioBuffer with proper sound data.
	 * @param data bytes from an MP3 file
	 * @return AudioBuffer, via AudioBuffer.fromBytes()
	 */
	public static function parseBytesMp3(data:Bytes):AudioBuffer
	{
		trace('incoming data length: ' + data.length);
		// need to find the first "frame" of the mp3 data, which would be a byte with the value 255
		// followed by a byte with the value where the value is 251, 250, or 243
		// reading
		// http://www.multiweb.cz/twoinches/mp3inside.htm#FrameHeaderA
		// http://mpgedit.org/mpgedit/mpeg_format/MP3Format.html
		// we start it as -1 so we can check the very first frame bytes (byte 0)
		var frameSyncBytePos = -1;
		// unsure if we need to keep track of the last frame, but doing so just in case
		var lastFrameSyncBytePos = 0;

		// BytesInput to read front to back of the data easier
		var byteInput:BytesInput = new BytesInput(data);

		for (byte in 0...data.length)
		{
			var byteValue = byteInput.readByte();
			var nextByte = data.get(byte + 1);

			// the start of a frame sync, which should be a byte with all bits set to 1 (255)
			if (byteValue == 255)
			{
				var mpegVersion = (nextByte & 0x18) >> 3; // gets the 4th and 5th bits of the next byte, for MPEG version
				var nextFrameSync = (nextByte & 0xE0) >> 5; // gets the first 3 bits of the next byte, which should be 111
				// i stole the values from "nextByte" from how Lime checks for valid mp3 frame data
				if (nextFrameSync == 7 && (nextByte == 251 || nextByte == 250 || nextByte == 243))
				{
					if (frameSyncBytePos == -1)
						frameSyncBytePos = byte;

					// assume this byte is the last frame sync byte we'll find
					lastFrameSyncBytePos = byte;
				}
			}
		}

		var bytesLength = lastFrameSyncBytePos - frameSyncBytePos;
		var output = Bytes.alloc(bytesLength + 1);

		trace("frameSyncBytePos: " + frameSyncBytePos);
		trace("lastFrameSyncBytePos: " + lastFrameSyncBytePos);
		trace("bytesLength: " + bytesLength);
		trace("data.length: " + data.length);
		output.blit(0, data, frameSyncBytePos, bytesLength);
		return AudioBuffer.fromBytes(output);
	}
}
