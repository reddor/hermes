# Hermes 

Hermes is a collection of techniques with the goal to create a single compressed file with Javascript and other resources, with demoscene usage in mind. En detail:

## Preprocessor
A simple pre-processor for file inclusion and conditionals. Supports DEFINE, UNDEFINE, IFDEF/ELSE/ENDIF, PRAGMA ONCE and INCLUDE. Preprocessor statements are prefixed //# so they can be treated as  

## Javascript Minifier
Minifying javascript by stripping comments and newlines, and renaming identifiers.
An keyword exclusion list has to be supplied so the tool knows which identifiers may not be altered (e.g. "window"). 

## Resource Support
Allows embedding binary data (e.g. webassembly) and other resources (e.g. workers).

## PNG Compression 
Everything is stored in a single png file to utilize its compression. Additional javascript payload  is embedded as a plaintext comment in the png, which is executed by the browser when served with the right mime-type (or file extension).

## Webserver & Hot Reload
An integrated webserver that allows automatic reloading once the content on disk change

# Known bugs
* Minifier does not support regular expressions
* Final result might not work in Firefox, depending on unknown factors and hardware configuration. (getImageData returns wrong data)
* Initial payload does not work with (old) Edge.
