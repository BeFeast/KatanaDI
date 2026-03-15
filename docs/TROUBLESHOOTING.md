# Troubleshooting

## No Sound

Check these first:

1. `KatanaDI` has microphone permission in `System Settings -> Privacy & Security -> Microphone`.
2. macOS sound output is set to `Built-in Output` or `Headphones`.
3. The app menu shows `Status: Active`.
4. The selected input channel is correct for the current Katana firmware and setup.

Known-good routing on the validated Intel setup:

- `Channel 3`
- `Mono -> Right`

## Microphone Prompt Never Appeared

If the app was launched before the bundle included the microphone usage description, macOS may not have prompted correctly.

Fix:

1. Quit the app.
2. Launch the current `.app` bundle again.
3. If still needed, enable `KatanaDI` manually in `System Settings -> Privacy & Security -> Microphone`.

Without microphone access the app can appear active while receiving silence from the input side.

## Output Device Error

If the app reports that system output must be `Built-in Output`, it means the current default output device does not match the route target.

Fix:

1. Open macOS Sound settings.
2. Set output to the built-in analog output.
3. If headphones are plugged in, `Headphones` is expected and still counts as the built-in output path.
4. Use `Refresh Route` in the menu.

## Which Output Channel Is Which

For the built-in analog output:

- `Output 1` is typically left
- `Output 2` is typically right

So if another tool works with `Input 3 -> Output 2`, the closest KatanaDI setting is:

- `Channel 3`
- `Mono -> Right`

## Diagnostics Do Not Move

When routing is healthy and you are playing, these should change:

- `Signal: input / output`
- `Callbacks: input / output`
- `Ring Buffer`

If `Callbacks` are increasing but `Signal` stays near zero, the likely causes are:

- wrong Katana input channel
- no signal coming from the instrument side
- microphone permission still denied

If `Signal: input` moves but `Signal: output` does not, the likely causes are:

- wrong output mode for the physical chain
- system output is not the built-in output
- output route needs a manual refresh

## Start At Login Does Not Work

`Start at Login` currently uses a LaunchAgent at:

`~/Library/LaunchAgents/com.oklabs.katanadi.plist`

Notes:

- when launched from a bundle, the LaunchAgent opens the `.app`
- when launched from a raw executable, the LaunchAgent stores that executable path
- moving or deleting the app after enabling login launch can break the stored path

Fix:

1. Put the app in a stable location, typically `/Applications`.
2. Disable `Start at Login`.
3. Enable it again.

## Long Session Glitches

The app already does lightweight buffer drift correction, but long sessions across independent devices still need more validation.

If you hear rare glitches during long play sessions:

1. try `128` or `256` samples
2. keep the route on the built-in output
3. use the diagnostics lines to see if `underflows` or `overflows` keep climbing

## Reconnect Problems

If the Katana was unplugged and replugged but audio did not come back:

1. wait a few seconds for the device monitor refresh
2. use `Refresh Route`
3. if needed, quit and relaunch the app

The route should usually recover automatically, but reconnect and sleep/wake behavior still need broader hardware validation.
