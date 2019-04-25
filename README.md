# Hermes 

Hermes is a collection of techniques with the goal to create a single file containing JavaScript & other resources that runs in the browser. En detail:

## Preprocessor
A simple pre-processor for file inclusion and conditionals. Preprocessor statements are prefixed with //# so they are treated as regular comments in normal environments.

Available directives:
* //#include [filename]
* //#define [identifier] [value]
* //#undefine [identifier]
* //#ifdef/ifndef [identifier], //#else & //#endif 
* //#export
* //#resource [identifier] [filename]
* //#pragma once (only include a file once)
* //#pragma localscope (if file was included, wrap it in ({ ... })() so all declarations remain inside a local scope. Auto-enabled if at least one export exists)

//#export is intended to make variables & methods in an include file publicly available, while putting the rest of the code inside a local scope. the //#export directive must be followed by either a *var* or a *function* declaration. As an additional bug/limitations, exported function declarations must be followed with a semicolon, e.g.:

    //#export
    function foobar() {
        alert(42);
    };

## Javascript Minifier
Reduces Javascript size by stripping comments and newlines, and renaming identifiers.
A keyword exclusion list has to be supplied so the tool knows which identifiers may not be altered (e.g. "document", "window"). The supplied list is incomplete, and *this is likely to be your number one pitfall* when using this feature.

## Resource Support
Allows embedding binary data (e.g. webassembly) and other resources (e.g. workers), using the //#resource directive. Resources can be accessed using the template's *resourcemanager.js*, e.g.:

    //#resource SYNTHBLOB output.wasm
    //#resource SYNTHWORKLET synthworklet.min.js
    
    // returns a Uint8Array
    getResourceArray(SYNTHBLOB)
    // returns a resource url with that mime-type
    getResourceUrl(SYNTHWORKLET, "application/javascript");

## PNG Compression 
Everything is stored in a single png file to utilize its compression. Additional javascript payload is embedded as a plaintext comment in the png, which is executed by the browser when served with the right mime-type (or file extension). This first payload loads itself as an image, then reads and executes the rest of the javascript encoded in the image.

Format is as follows:

size | type
---- | ----
? | javascript
1 | null terminator (0x00)
? | resources 
? | resource-table
1 | resource count
? | padding data (0xff)

To read javascript from the png, simply read pixel data from the start until you encounter the null terminator (0x00). Check out template/resourcemanager.js to find out on how resources are read. 

## Webserver & Hot Reload
The integrated webserver allows hot reloading whenever the content on disk changes. 
Hot reload is only available on Windows, but a rebuild can also be manually triggered in the browser.

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

## Getting started
Duplicate the "template" directory and run watch.bat - then open http://127.0.0.1:8099 

# Known bugs
* No support for regular expressions
* Final result might not work in Firefox, depending on unknown factors and hardware configuration. (getImageData returns wrong data)
* PNG payload/decompression does not work with Edge.
* No unicode

# Compiling
Use Lazarus to compile, e.g.:

    lazbuild hermes.lpi

No additional dependencies required. Windows/Linux tested, although it *should* compile for other targets as well. 

## Compiling the WebAssembly example
    emcc fakesynth.c -Os -s WASM=1 -s "SIDE_MODULE=1" -s BINARYEN_TRAP_MODE=clamp -s TOTAL_MEMORY=268435456 -o output.wasm
(tested with version 1.38.28)

# Credits
* http://www.ararat.cz/synapse/doku.php/start Arat Synapse for socket related things
* whoever came up with the png compression trick
