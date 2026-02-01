package funkin.util.flixel.sound;

import flixel.FlxG;
import haxe.Int64;
import haxe.io.Bytes;
import haxe.io.Path;
import lime.app.Future;
import lime.app.Promise;
#if (js && html5 && lime_howlerjs)
import lime.media.howlerjs.Howl;
#end
import lime.media.AudioBuffer;
import lime.media.AudioDecoder;
import lime.system.ThreadPool;
import lime.utils.UInt8Array;
import openfl.media.Sound;
import openfl.utils.Assets;

class FlxPartialSound
{
	public static var cache:Map<String, Sound> = [];

	public static function clearCache():Void
	{
		for (key in cache.keys())
		{
			var sound:Null<Sound> = cache.get(key);
			if (sound != null)
			{
				Assets.cache.removeSound(key);
				cache.remove(key);
			}
		}
	}

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
		var promise:Promise<Sound> = new Promise<Sound>();
		var cacheName:String = audioPath + ".partial-" + rangeStart + "-" + rangeEnd;

		if (Assets.cache.hasSound(cacheName))
		{
			promise.complete(Assets.cache.getSound(cacheName));

			return promise;
		}

		#if (lime_funkin && (js && html5) && lime_howlerjs)
		partialLoadHowlerSprite(cacheName, promise, audioPath, rangeStart, rangeEnd);
		#elseif (lime_funkin && (lime_cffi && !macro))
		partialLoadAudioDecoder(cacheName, promise, audioPath, rangeStart, rangeEnd);
		#end

		return promise;
	}

	#if (lime_funkin && (js && html5) && lime_howlerjs)
	@:access(lime.media.AudioBuffer)
	@:noCompletion
	private static function partialLoadHowlerSprite(cacheName:String, promise:Promise<Sound>, audioPath:String, ?rangeStart:Float = 0, ?rangeEnd:Float = 1):Void
	{
		// TODO: If the library that contains the sound isnt preloaded, this fails, so for now, just force load it
		// if (!Assets.exists(audioPath, SOUND))
		// {
		// 	trace("Could not find audio file for partial playback: " + audioPath);
		// 	return;
		// }

		var promiseGotHowlerBuffer:Promise<AudioBuffer> = new Promise<AudioBuffer>();

		promiseGotHowlerBuffer.future.onComplete(function(audioBuffer:AudioBuffer):Void
		{
			var sndShit = Sound.fromAudioBuffer(audioBuffer);
			Assets.cache.setSound(cacheName, sndShit);
			cache.set(cacheName, sndShit);
			promise.complete(sndShit);
		});

		var audioBuffer = new AudioBuffer();

		audioBuffer.__srcHowlerDefaultSprite = "main";

		function onHowlerLoad():Void
		{
			var duration = audioBuffer.__srcHowl.duration();
			var start = Math.round(duration * rangeStart * 1000);
			var end = Math.round(duration * rangeEnd * 1000);

			untyped audioBuffer.__srcHowl._sprite = {main: [start, end - start]};

			promiseGotHowlerBuffer.complete(audioBuffer);
		}

		// TODO: If the library that contains the sound isnt preloaded, this fails, so for now, just force load it
		// audioBuffer.__srcHowl = new Howl({src: [Assets.getPath(audioPath)], preload: true, onload: onHowlerLoad});
		audioBuffer.__srcHowl = new Howl({src: [audioPath], preload: true, onload: onHowlerLoad});
	}
	#end

	#if (lime_funkin && (lime_cffi && !macro))
	private static function partialLoadAudioDecoder(cacheName:String, promise:Promise<Sound>, audioPath:String, ?rangeStart:Float = 0, ?rangeEnd:Float = 1):Void
	{
		if (!Assets.exists(audioPath, SOUND))
		{
			trace("Could not find audio file for partial playback: " + audioPath);
			return;
		}

		var threadPool:ThreadPool = new ThreadPool();

		function doWork(state:Dynamic, output:Dynamic):Void
		{
			var audioDecoder:AudioDecoder = AudioDecoder.fromFile(Assets.getPath(audioPath));

			if (audioDecoder == null)
			{
				audioDecoder = AudioDecoder.fromBytes(Assets.getBytes(audioPath));
			}

			if (audioDecoder == null)
			{
				promise.error("Unsupported file type: " + Path.extension(audioPath));
				return;
			}

			var totolFrames:Int = Int64.toInt(audioDecoder.total());
			var framesStart:Int = Std.int(totolFrames * rangeStart);
			var framesEnd:Int = Std.int(totolFrames * rangeEnd);

			audioDecoder.seek(framesStart);

			var audioBuffer:AudioBuffer = new AudioBuffer();
			audioBuffer.sampleRate = audioDecoder.sampleRate;
			audioBuffer.channels = audioDecoder.channels;
			audioBuffer.dataFormat = S16;
			audioBuffer.data = UInt8Array.fromBytes(audioDecoder.decode(framesEnd - framesStart, audioBuffer.dataFormat));
			threadPool.sendComplete({audioBuffer: audioBuffer});
		}

		threadPool.onComplete.add(function(data:Dynamic):Void
		{
			var sndShit = Sound.fromAudioBuffer(audioBuffer);
			Assets.cache.setSound(cacheName, sndShit);
			cache.set(cacheName, sndShit);
			promise.complete(sndShit);
		});

		threadPool.onError.add(function(_):Void
		{
			promise.error(_);
		});

		threadPool.queue(doWork);
	}
	#end
}
