package funkin.util.flixel.sound;

import flixel.FlxG;
import haxe.io.Bytes;
import haxe.io.BytesInput;
import haxe.io.Path;
import lime.app.Future;
import lime.app.Promise;
import lime.media.AudioBuffer;
import lime.net.HTTPRequest;
import lime.net.HTTPRequestHeader;
import openfl.media.Sound;
import openfl.utils.Assets;

#if lime_vorbis
import lime.media.vorbis.VorbisFile;
#end

using StringTools;

class FlxPartialSound
{
	/**
	 * Loads partial sound bytes from a file, returning a Sound object.
	 * Will play the sound after loading via FlxG.sound.play()
	 * @param path
	 * @param rangeStart what percent of the song should it start at
	 * @param rangeEnd what percent of the song should it end at
	 * @return Future<Sound>
	 */
	public static function partialLoadAndPlayFile(path:String, ?rangeStart:Float = 0, ?rangeEnd:Float = 1):Future<Sound>
	{
		return partialLoadFromFile(path, rangeStart, rangeEnd).future.onComplete(function(sound:Sound)
		{
			FlxG.sound.play(sound);
		});
	}

	/**
	 * Loads partial sound bytes from a file, returning a Sound object.
	 * Will load via HTTP Range header on HTML5, and load the bytes from the file on native.
	 * On subsequent calls, will return a cached Sound object from Assets.cache
	 * @param path
	 * @param rangeStart what percent of the song should it start at
	 * @param rangeEnd what percent of the song should it end at
	 * @return Future<Sound>
	 */
	public static function partialLoadFromFile(path:String, ?rangeStart:Float = 0, ?rangeEnd:Float = 1, ?paddedIntro:Bool = false):Promise<Sound>
	{
		var promise:Promise<Sound> = new Promise<Sound>();

		if (Assets.cache.hasSound(path + ".partial-" + rangeStart + "-" + rangeEnd))
		{
			promise.complete(Assets.cache.getSound(path + ".partial-" + rangeStart + "-" + rangeEnd));
			return promise;
		}

		#if web
		requestContentLength(path).onComplete(function(contentLength:Int)
		{
			var startByte:Int = Std.int(contentLength * rangeStart);
			var endByte:Int = Std.int(contentLength * rangeEnd);
			var byteRange:String = startByte + '-' + endByte;

			// for ogg files, we want to get a certain amount of header info stored at the beginning of the file
			// which I believe helps initiate the audio stream properly for any section of audio
			// 0-6400 is a random guess, could be fuckie with other audio
			if (Path.extension(path) == "ogg")
				byteRange = '0-' + Std.string(16 * 400);

			var http = new HTTPRequest<Bytes>(path);
			var rangeHeader:HTTPRequestHeader = new HTTPRequestHeader("Range", "bytes=" + byteRange);
			http.headers.push(rangeHeader);

			http.load().onComplete(function(data:Bytes)
			{
				var audioBuffer:AudioBuffer = new AudioBuffer();
				switch (Path.extension(path))
				{
					case "mp3":
						var mp3Data = parseBytesMp3(data, startByte);
						audioBuffer = mp3Data.buf;


						var snd = Sound.fromAudioBuffer(audioBuffer);
						Assets.cache.setSound(path + ".partial-" + rangeStart + "-" + rangeEnd, snd);
						PartialSoundMetadata.instance.set(path + rangeStart, {kbps:mp3Data.kbps, introOffsetMs:mp3Data.introLengthMs});
						promise.complete(snd);

					case "ogg":
						var httpFull = new HTTPRequest<Bytes>(path);

						rangeHeader = new HTTPRequestHeader("Range", "bytes=" + startByte + '-' + endByte);
						httpFull.headers.push(rangeHeader);
						httpFull.load().onComplete(function(fullOggData)
						{
							var cleanIntroBytes = cleanOggBytes(data);
							var cleanFullBytes = cleanOggBytes(fullOggData);
							var fullBytes = Bytes.alloc(cleanIntroBytes.length + cleanFullBytes.length);
							fullBytes.blit(0, cleanIntroBytes, 0, cleanIntroBytes.length);
							fullBytes.blit(cleanIntroBytes.length, cleanFullBytes, 0, cleanFullBytes.length);

							audioBuffer = parseBytesOgg(fullBytes, true);
							Assets.cache.setSound(path + ".partial-" + rangeStart + "-" + rangeEnd, Sound.fromAudioBuffer(audioBuffer));
							promise.complete(Sound.fromAudioBuffer(audioBuffer));
						});

					default:
						promise.error("Unsupported file type: " + Path.extension(path));
				}
			});
		});

		return promise;
		#else
		if (!Assets.exists(path))
		{

			FlxG.log.warn("Could not find audio file for partial playback: " + path);
			return null;
		}

		// on native, it will always be an ogg file, although eventually we might want to add WAV?
		Assets.loadBytes(path).onComplete(function(data:openfl.utils.ByteArray)
		{
			#if lime_vorbis
			// loading it via VorbisFile will set the NativeAudioSource stuff to use streaming audio to decode the ogg
			// rather than any manual decoding / parsing us or lime needs to do
			var vorbisFile:VorbisFile = VorbisFile.fromBytes(data);
			var audioBuffer:AudioBuffer = AudioBuffer.fromVorbisFile(vorbisFile);
			var sndShit = Sound.fromAudioBuffer(audioBuffer);
			Assets.cache.setSound(path + ".partial-" + rangeStart + "-" + rangeEnd, sndShit);
			promise.complete(sndShit);
			#else
			var input = new BytesInput(data);
			var size = input.length;

			switch (Path.extension(path))
			{
				case "ogg":
					var oggBytesAsync = new Future<Bytes>(function()
					{
						var oggBytesIntro = Bytes.alloc(16 * 400);
						for (i in 0...oggBytesIntro.length)
						{
							oggBytesIntro.set(i, input.readByte());
						}
						return cleanOggBytes(oggBytesIntro);
					}, true);

					oggBytesAsync.onComplete(function(oggBytesIntro:Bytes)
					{
						var oggRangeMin:Float = rangeStart * size;
						var oggRangeMax:Float = rangeEnd * size;
						var oggBytesFull = Bytes.alloc(Std.int(oggRangeMax - oggRangeMin));

						input.position = Std.int(oggRangeMin);

						var fullBytesAsync = new Future<Bytes>(function()
						{
							for (i in 0...oggBytesFull.length)
							{
								oggBytesFull.set(i, input.readByte());
							}

							return cleanOggBytes(oggBytesFull);
						}, true);

						fullBytesAsync.onComplete(function(fullAssOgg:Bytes)
						{
							var oggFullBytes = Bytes.alloc(oggBytesIntro.length + fullAssOgg.length);
							oggFullBytes.blit(0, oggBytesIntro, 0, oggBytesIntro.length);
							oggFullBytes.blit(oggBytesIntro.length, fullAssOgg, 0, fullAssOgg.length);
							input.close();

							var audioBuffer:AudioBuffer = parseBytesOgg(oggFullBytes, true);

							var sndShit = Sound.fromAudioBuffer(audioBuffer);
							Assets.cache.setSound(path + ".partial-" + rangeStart + "-" + rangeEnd, sndShit);
							promise.complete(sndShit);
						});
					});

				default:
					promise.error("Unsupported file type: " + Path.extension(path));
			}
			#end // lime_vorbis check

		});

		return promise;
		#end // web/sys check
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
	 * @param startByte how many bytes into the original audio are we reading from, to use to calculate extra metadata (introLengthMs)
	 * @return {buf:AudioBuffer, kbps:Int, introLengthMs:Int} AudioBuffer, kbps of the audio, and the length of the intro in milliseconds
	 */
	public static function parseBytesMp3(data:Bytes, ?startByte:Int = 0):{buf:AudioBuffer, ?kbps:Int, ?introLengthMs:Int}
	{
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

		// How many mp3 frames we found
		var frameCount:Int = 0;

		var bitrateAvg:Map<Int, Int> = new Map();

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
					frameCount++;

					var byte2 = data.get(byte + 2);
					var bitrateIndex = (byte2 & 0xF0) >> 4;
					var bitrateArray = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320];
					var bitrate = bitrateArray[bitrateIndex];

					var samplingRateIndex = (byte2 & 0x0C) >> 2;
					var sampleRateArray = [44100, 48000, 32000];
					var sampleRate = sampleRateArray[samplingRateIndex];

					bitrateAvg[bitrate] = bitrateAvg.exists(bitrate) ? bitrateAvg.get(bitrate) + 1 : 1;


					if (frameSyncBytePos == -1)
						frameSyncBytePos = byte;

					// assume this byte is the last frame sync byte we'll find
					lastFrameSyncBytePos = byte;
				}
			}
		}

		// what we'll actually return
		var outputInfo:Dynamic = {};

		var mostCommonBitrate = 0;
		for (bitrate in bitrateAvg.keys())
		{
			if (bitrateAvg.get(bitrate) > bitrateAvg.get(mostCommonBitrate))
				mostCommonBitrate = bitrate;
		}

		// bitrate is in bits rather than kilobits, so we're getting the milliseconds of the intro
		// also since it's in bits, we divide by 8 to get bytes
		var introLengthMs:Int = Math.round(startByte / (mostCommonBitrate / 8));

		// length of an mp3 frame in milliseconds
		var frameLengthMs:Float = 26;

		// how many frames we need to pad the intro with
		var framesNeeded = Math.floor(introLengthMs / frameLengthMs);

		outputInfo.introLengthMs = introLengthMs;
		outputInfo.kbps = mostCommonBitrate;

		var bytesLength = lastFrameSyncBytePos - frameSyncBytePos;
		var bufferBytes = Bytes.alloc(bytesLength + 1);
		bufferBytes.blit(0, data, frameSyncBytePos, bytesLength);

		outputInfo.buf = AudioBuffer.fromBytes(bufferBytes);
		return outputInfo;
	}

	public static function parseBytesOgg(data:Bytes, skipCleaning:Bool = false):AudioBuffer
	{
		var cleanedBytes = skipCleaning ? data : cleanOggBytes(data);
		return AudioBuffer.fromBytes(cleanedBytes);
	}

	static function cleanOggBytes(data:Bytes):Bytes
	{
		var byteInput:BytesInput = new BytesInput(data);
		var firstByte:Int = -1;
		var lastByte:Int = -1;
		var oggString:String = "";

		for (byte in 0...data.length)
		{
			var byteValue = byteInput.readByte();

			if (byteValue == "O".code || byteValue == "g".code || byteValue == "S".code)
				oggString += String.fromCharCode(byteValue);
			else
				oggString = "";

			if (oggString == "OggS")
			{
				if (firstByte == -1)
				{
					firstByte = byte - 3;
					data.set(byte + 2, 2);
				}

				lastByte = byte - 3;

				var version = data.get(byte + 1);
				var headerType = data.get(byte + 2);
			}
		}

		var byteLength = lastByte - firstByte;
		var output = Bytes.alloc(byteLength + 1);
		output.blit(0, data, firstByte, byteLength);

		return output;
	}
}
