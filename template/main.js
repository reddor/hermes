//#include resourcemanager.js

// clean up html body...
document.body.removeChild(document.body.firstChild);
c.style.display = "none";

//#include synth.js
//you might want to call this during an onclick-event so browser-policies don't suspend the audio context... 
InitSynth();