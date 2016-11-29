# NLHue
## An EventMachine-based Ruby library for interfacing with the Philips Hue lighting system.

&copy;2012-2016 Mike Bourgeous, Nitrogen Logic

This Gem was created because in 2012 many of the other fine Ruby Hue libraries
lacked a clear license agreement, were only partially implemented, and/or
required far too many third-party Gems for my use.

NLHue uses an asynchronous callback-based API built on EventMachine.  It's not
exactly easy to use, and not recommended for non-EventMachine-based
applications.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'nlhue'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install nlhue

## Usage

TODO: Write usage instructions here

## Useful info

### Working with Hue using cURL

Useful command-line stuff:

```bash
HUE_IP=[x.x.x.x]
HUE_KEY=[hue_api_key]
alias off='curl -X PUT -d '\''{"on":false}'\'' http://${HUE_IP}/api/${HUE_KEY}/lights/2/state ; echo'
alias on='curl -X PUT -d '\''{"on":true}'\'' http://${HUE_IP}/api/${HUE_KEY}/lights/2/state ; echo'
alias pink='curl -X PUT -d '\''{"hue":58000,"sat":254,"bri":254,"transitiontime":0}'\'' http://${HUE_IP}/api/${HUE_KEY}/lights/2/state ; echo'
alias purple='curl -X PUT -d '\''{"hue":48400,"sat":254,"bri":254,"transitiontime":0}'\'' http://${HUE_IP}/api/${HUE_KEY}/lights/2/state ; echo'
alias red='curl -X PUT -d '\''{"hue":0,"sat":254,"bri":254,"transitiontime":0}'\'' http://${HUE_IP}/api/${HUE_KEY}/lights/2/state ; echo'
alias green='curl -X PUT -d '\''{"hue":21844,"sat":254,"bri":254,"transitiontime":0}'\'' http://${HUE_IP}/api/${HUE_KEY}/lights/2/state ; echo'
alias blue='curl -X PUT -d '\''{"hue":46774,"sat":254,"bri":254,"transitiontime":0}'\'' http://${HUE_IP}/api/${HUE_KEY}/lights/2/state ; echo'
hue() { M="{\"hue\":$(($1 * 182)),\"sat\":254,\"bri\":254,\"transitiontime\":10}" ; curl -X PUT -d "$M" http://${HUE_IP}/api/${HUE_KEY}/lights/2/state; echo; }
```

### Notes on Hue scenes

> Recalling a scene with curl (always posted to group 0):
>
> ```bash
> curl -X PUT http://[ip]/api/[key]/groups/0/action --data-binary '{"scene":"4170a6910-on-0"}'
> ```
>
> It seems like scenes with "fon" in the name (or any number other than 0 after
> -on-) should be ignored.
>
> If multiple scenes of the same name exist ending in -on-0 or -off-0, choose the
> one with the highest timestamp?  It's possible that only the Hue app creates
> timestamps, so don't assume they will be there.
>
> Typical scene ID from Hue app: "xxxxxxxxx-on-0"
> Typical scene name from app: "Scene Name (on|off|fon) [timestamp]"
>
> Sometimes the timestamp is abbreviated to 5 digits, but it's typically the
> number of milliseconds since 1970-01-01.
>
> --
>
> After further investigation it looks like the "-on-2"/"-on-4" scenes are fade
> in times of 2 and 4 minutes, and the "fon" in the middle of a scene name means
> "fade on".  The transitiontime parameter doesn't work when recalling a scene.
> The transition time is saved with the scene.
>
> See http://www.everyhue.com/vanilla/discussion/1124/scenes-api
>
> --
>
> *Recalling a scene on a group other than 0 seems to limit the scene's effects to
> the lights in that group.*


## License

NLHue is licensed under the two-clause BSD license.
