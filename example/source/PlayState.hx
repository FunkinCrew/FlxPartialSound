package;

import flixel.FlxG;
import flixel.FlxState;
import funkin.util.flixel.sound.FlxPartialSound;
import haxe.io.BytesInput;
import haxe.io.Input;
import lime.media.AudioBuffer;
import lime.net.HTTPRequest;
import lime.net.HTTPRequestHeader;
import lime.utils.Bytes;
import openfl.media.Sound;
import openfl.utils.ByteArray;

class PlayState extends FlxState
{
	override public function create()
	{
		super.create();

		var sndRequest = FlxPartialSound.partialLoadFromFile("assets/music/Pico.mp3", 0.2, 0.5);

		sndRequest.onComplete(function(buffer:AudioBuffer)
		{
			var snd:Sound = Sound.fromAudioBuffer(buffer);
			FlxG.sound.play(snd);
		});
		// snd.loadCompressedDataFromByteArray(ByteArray.fromBytes(data), data.length);
	}

	override public function update(elapsed:Float)
	{
		super.update(elapsed);
	}
}
