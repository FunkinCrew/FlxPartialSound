package funkin.util.flixel.sound;

import flixel.FlxG;
import lime.app.Future;
import lime.app.Promise;
import lime.media.AudioBuffer;
import openfl.media.Sound;
import openfl.utils.Assets;
#if (lime_funkin && (js && html5 && lime_howlerjs))
import lime.media.howlerjs.Howl;
import lime.media.howlerjs.Howler;
#elseif (lime_funkin && (lime_cffi && lime_miniaudio && !macro))
import haxe.Int64;
import haxe.io.Bytes;
import lime.media.miniaudio.MADataFormat;
import lime.media.miniaudio.MADecoder;
import lime.media.miniaudio.MADecoderConfig;
import lime.media.miniaudio.MAHelpers;
import lime.system.ThreadPool;
import lime.system.WorkOutput;
import lime.utils.Int16Array;
#end

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
	 * @param rangeStart what percent of the song (between 0 and 1) should it start at
	 * @param rangeEnd what percent of the song should it end at
	 * @return Future<Sound>
	 */
	public static function partialLoadFromFile(audioPath:String, ?rangeStart:Float = 0, ?rangeEnd:Float = 1, ?paddedIntro:Bool = false):Promise<Sound>
	{
		return partialLoadInternal(audioPath, rangeStart, rangeEnd, null);
	}

	public static function partialLoadFromBytes(audioPath:String, audioBytes:haxe.io.Bytes, ?rangeStart:Float = 0, ?rangeEnd:Float = 1):Promise<Sound>
	{
		return partialLoadInternal(audioPath, rangeStart, rangeEnd, audioBytes);
	}

	private static function partialLoadInternal(audioPath:String, rangeStart:Float, rangeEnd:Float, preloadedBytes:Null<haxe.io.Bytes>):Promise<Sound>
	{
		var promise:Promise<Sound> = new Promise<Sound>();
		var cacheName:String = audioPath + ".partial-" + rangeStart + "-" + rangeEnd;

		if (Assets.cache.hasSound(cacheName))
		{
			promise.complete(Assets.cache.getSound(cacheName));

			return promise;
		}

		#if (lime_funkin && (js && html5) && lime_howlerjs)
		partialLoadHowlerSprite(cacheName, promise, audioPath, rangeStart, rangeEnd, preloadedBytes);
		#elseif (lime_funkin && (lime_cffi && !macro) && lime_miniaudio)
		partialLoadMADecoder(cacheName, promise, audioPath, rangeStart, rangeEnd);
		#end

		return promise;
	}

	#if (lime_funkin && (js && html5) && lime_howlerjs)
	@:access(lime.media.AudioBuffer)
	@:noCompletion
	private static function partialLoadHowlerSprite(cacheName:String, promise:Promise<Sound>, audioPath:String, rangeStart:Float, rangeEnd:Float, preloadedBytes:Null<haxe.io.Bytes>):Void
	{
		var fileBytes:Null<haxe.io.Bytes> = preloadedBytes;
		var audioUrl:String = audioPath;
		var audioObjectUrl:Null<String> = null;

		if (fileBytes == null && Assets.exists(audioPath, SOUND) && Assets.isLocal(audioPath, SOUND))
			fileBytes = Assets.getBytes(audioPath);

		if (fileBytes != null)
		{
			@:privateAccess
			var type:String = AudioBuffer.__getCodec(fileBytes);

			if (Howler.usingWebAudio)
			{
				audioObjectUrl = js.Syntax.code("URL.createObjectURL(new Blob([{0}], { type: {1} }))", fileBytes.getData(), type);
				audioUrl = audioObjectUrl;
			}
			else
			{
				audioUrl = 'data:${type};base64,${haxe.crypto.Base64.encode(fileBytes)}';
			}
		}

		var promiseGotHowlerBuffer:Promise<AudioBuffer> = new Promise<AudioBuffer>();

		promiseGotHowlerBuffer.future.onComplete(function(audioBuffer:AudioBuffer):Void
		{
			var sndShit = Sound.fromAudioBuffer(audioBuffer);
			Assets.cache.setSound(cacheName, sndShit);
			promise.complete(sndShit);
		});

		var audioBuffer = new AudioBuffer();

		audioBuffer.__srcHowlerDefaultSprite = "main";

		function releaseObjectUrl():Void
		{
			if (audioObjectUrl != null)
			{
				js.Syntax.code("URL.revokeObjectURL({0})", audioObjectUrl);
				audioObjectUrl = null;
			}
		}

		function onHowlerLoad():Void
		{
			releaseObjectUrl();

			var duration = audioBuffer.__srcHowl.duration();
			var start = Math.round(duration * rangeStart * 1000);
			var end = Math.round(duration * rangeEnd * 1000);

			untyped audioBuffer.__srcHowl._sprite = {main: [start, end - start]};

			promiseGotHowlerBuffer.complete(audioBuffer);
		}

		var audioOptions:Dynamic = {src: [audioUrl], preload: true, onload: onHowlerLoad};
		audioOptions.onloaderror = function(_id:Dynamic, error:Dynamic):Void
		{
			releaseObjectUrl();
			promise.error(error);
		};

		var audioFormat:String = Path.extension(audioPath);
		if (audioFormat.length > 0) audioOptions.format = [audioFormat];
		audioBuffer.__srcHowl = new Howl(audioOptions);
	}
	#end

	#if (lime_funkin && (lime_cffi && !macro) && lime_miniaudio)
	@:noCompletion
	static var localThreadPool:ThreadPool;

	@:noCompletion
	private static function partialLoadMADecoder(cacheName:String, promise:Promise<Sound>, audioPath:String, ?rangeStart:Float = 0, ?rangeEnd:Float = 1):Void
	{
		if (preloadedBytes == null && !Assets.exists(audioPath, SOUND))
		{
			trace("Could not find audio file for partial playback: " + audioPath);
			return;
		}

		if (localThreadPool == null)
		{
			localThreadPool = new ThreadPool(0, 2);
			localThreadPool.onComplete.add(localThreadPool_onComplete);
			localThreadPool.onError.add(localThreadPool_onError);
		}

		localThreadPool.run(localThreadPool_doWork, {
			cacheName: cacheName,
			promise: promise,
			audioPath: audioPath,
			rangeStart: rangeStart,
			rangeEnd: rangeEnd,
			preloadedBytes: preloadedBytes
		});
	}

	@:noCompletion
	private static function localThreadPool_doWork(state:Dynamic, output:WorkOutput):Void
	{
		var decoder:MADecoder = MADecoder.init_file(state.audioPath, MADecoderConfig.init(S16, 0, 0));

		if (decoder == null)
		{
			decoder = MADecoder.init_memory(Assets.getBytes(state.audioPath), MADecoderConfig.init(S16, 0, 0));
		}

		if (decoder != null)
		{
			var totalFrames:Int = Int64.toInt(decoder.get_length_in_pcm_frames());

			if (totalFrames > 0)
			{
				var framesStart:Int = Std.int(totalFrames * state.rangeStart);
				var framesEnd:Int = Std.int(totalFrames * state.rangeEnd);
				var framesToRead:Int = framesEnd - framesStart;

				var dataFormat:MADataFormat = decoder.get_data_format();
				var bytesPerSample:Int = MAHelpers.get_bytes_per_sample(dataFormat.format);
				var dataBuffer:Int16Array = new Int16Array(Bytes.alloc(framesToRead * dataFormat.channels * bytesPerSample));

				decoder.seek_to_pcm_frame(framesStart);

				if (decoder.read_pcm_frames(#if cpp cpp.Pointer.ofArray(dataBuffer.buffer.getData()) #else null #end, framesToRead) > 0)
				{
					if (decoder != null)
					{
						decoder.uninit();
						decoder = null;
					}

					var audioBuffer = new AudioBuffer();

					audioBuffer.sampleRate = dataFormat.sampleRate;
					audioBuffer.channels = dataFormat.channels;
					audioBuffer.format = dataFormat.format;
					audioBuffer.frames = framesToRead;
					audioBuffer.data = dataBuffer;

					output.sendComplete({
						state: state,
						audioBuffer: audioBuffer
					});

					return;
				}
			}
		}

		output.sendError({
			state: state,
			message: "Cannot load file: " + state.path
		});
	}

	@:noCompletion
	private static function localThreadPool_onComplete(data:Dynamic):Void
	{
		var sndShit = Sound.fromAudioBuffer(data.audioBuffer);
		Assets.cache.setSound(data.state.cacheName, sndShit);
		data.state.promise.complete(sndShit);
	}

	@:noCompletion
	private static function localThreadPool_onError(data:Dynamic):Void
	{
		data.state.promise.error(data.message);
	}
	#end
}
