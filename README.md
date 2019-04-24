# Hermes 

Hermes is a collection of techniques with the goal to create a single file containing JavaScript & other resources, that runs in the browser. En detail:

## Preprocessor
A simple pre-processor for file inclusion and conditionals. Supports DEFINE, UNDEFINE, IFDEF/ELSE/ENDIF, PRAGMA ONCE and INCLUDE. Preprocessor statements are prefixed with //# so they can be treated as  

## Javascript Minifier
Reduces Javascript size by stripping comments and newlines, and renaming identifiers.
An keyword exclusion list has to be supplied so the tool knows which identifiers may not be altered (e.g. "document", "window"). The supplied list is incomplete, and this is likely to be your number one pitfall when using this feature.

## Resource Support
Allows embedding binary data (e.g. webassembly) and other resources (e.g. workers). Example code on how to access resources and get them in various representations (url, blob, array, string) is supplied.

## PNG Compression 
Everything is stored in a single png file to utilize its compression. Additional javascript payload is embedded as a plaintext comment in the png, which is executed by the browser when served with the right mime-type (or file extension).

## Webserver & Hot Reload
The integrated webserver allows hot reloading whenever the content on disk changes. 

# Usage
    hermes.exe [-csrvxyz] [-server <port>] <input js file> <output html file>
    
             -server <port>  be a webserver and serve directory of input file
             -c              strip comments
             -s              strip spaces
             -r              strip newlines
             -m              minify
             -v              verbose
             -x              reuse strings
             -y              reuse identifiers
* -x and -y are experimental features and tend to make the end result bigger )

# Known bugs
* Minifier does not support regular expressions
* Final result might not work in Firefox, depending on unknown factors and hardware configuration. (getImageData returns wrong data)
* PNG payload/decompression does not work with Edge.

# Compiling
Use Lazarus to compile, e.g.:

    lazbuild hermes.lpi

No additional dependencies required. Windows/Linux tested, although it *should* compile for other targets as well. 

## Compiling the WebAssembly example
    emcc fakesynth.c -Os -s WASM=1 -s "SIDE_MODULE=1" -s BINARYEN_TRAP_MODE=clamp -s TOTAL_MEMORY=268435456 -o output.wasm
(tested with version 1.38.28)

# Credits
* http://www.ararat.cz/synapse/doku.php/start Arat Synapse for socket related things
