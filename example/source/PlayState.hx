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

		FlxPartialSound.partialLoadAndPlayFile("assets/music/Senpai.ogg", 0.1, 0.2);
		// snd.loadCompressedDataFromByteArray(ByteArray.fromBytes(data), data.length);
	}

	override public function update(elapsed:Float)
	{
		super.update(elapsed);

		if (FlxG.keys.justPressed.SPACE)
		{
			FlxG.sound.defaultSoundGroup.pause();
			FlxPartialSound.partialLoadAndPlayFile("assets/music/Senpai.ogg", 0.1, 0.2);
		}
	}
}
