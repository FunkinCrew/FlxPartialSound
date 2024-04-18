# FlxPartialSound

Haxelib for haxeflixel for loading partial data from an audio file

## Usage

```hx

// will load audio asset "assets/music/music.mp3" from bytes near 10% (0.1) of the audio lenght, 
// until the bytes around 50% (0.5) of the audio length
// which will return a Future<AudioBuffer>
var soundRequest = FlxPartialSound.partialLoadFromFile('assets/music/music.mp3', 0.1, 0.5);

// once it finishes loading, we can play it with flixel
soundRequest.onComplete(function(buffer:AudioBuffer)
{
	FlxG.sound.play(Sound.fromAudioBuffer(buffer));
});
```

Requires `lime` and `flixel`

# TODO

See the [Github Issues](https://github.com/FunkinCrew/FlxPartialSound/issues)

## Restrictions

### Loading via percentage values

You need to load it via "percentage" values since:
- Varying bitrates aren't supported, so it just gets the first "frame" of MP3 data it finds
- sample rate also isn't supported yet.

So while it would be nice to supply it via milliseconds, that would require:
- requesting the audio file
- getting the file type (MP3 or OGG)
- getting the sample rate data from the byte data
- getting the bitrate data from the byte data


## Further reading and research material

- [MP3 inside (mp3 file format and headers info)](http://www.multiweb.cz/twoinches/mp3inside.htm)
- [MPEG Audio Layer I/II/III frame header (more mp3 file header info)](http://mpgedit.org/mpgedit/mpeg_format/MP3Format.html)
- [MDN Docs: Range HTTP header](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Range)
