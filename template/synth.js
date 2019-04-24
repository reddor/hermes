//#include resourcemanager.js

/* Audio worklets are a convenient way to render audio in a thread - sadly it's currently only supported
   with chrome. However, running your synth in the main thread might cause frame drops. */

//.#define USE_AUDIOWORKLETS 

/* referencing the webassembly blob here, which will cause it to be embedded in the final result. */ 
//#resource SYNTHBLOB output.wasm

var context;

//#export
function getSynthTime()
{
    return context ? context.currentTime : 0;
};

//#export
function InitSynth() {
  if (context) return;

//#ifdef USE_AUDIOWORKLETS

/* For the audio worklet, we need a separate resource/script file which contains the worklet code. 
   As this is treated as a binary resource, we must manually use a minified version if we care for the size.*/
//#resource SYNTHWORKLET synthworklet.min.js

  context = new AudioContext({suspended: true});    
  var blob = getResourceUrl(SYNTHWORKLET, "application/javascript");
  context.audioWorklet.addModule(blob).then(() => {
      synthnode = new AudioWorkletNode(context, "wasmsynth", {"numberOfInputs":0, "numberOfOutputs": 1, "outputChannelCount":[2]});
      /* send context's samplerate and webassembly blob to worklet, rest is handled there */
      synthnode.port.postMessage({"t":"init","b":getResourceArray(SYNTHBLOB),"sr":context.sampleRate});
      synthnode.connect(context.destination);
      context.resume();
  });

//#else
/* otherwise we load the webassembly first, and create a script processor node where we call the render proc */

var importObject = {
    'env': {
      '__memory_base': 0,
        '__table_base': 0,
        'memory': new WebAssembly.Memory({initial: 8192}),
        'table': new WebAssembly.Table({initial: 8192, element: 'anyfunc'}) ,
      'abort': e => alert(e),
      '_cosf': Math.cos,
      '_sinf': Math.sin,
      '_llvm_exp2_f32': (x, y) => y ? x * Math.pow(2, y) : Math.pow(2, x),
    }	 
  }; 
  
  WebAssembly.instantiate(getResourceArray(SYNTHBLOB), importObject).then(r => {
    context = new AudioContext();
    let synth = r.instance;
    synth.exports["__post_instantiate"]();
    synth.exports["_initializeSynth"](context.sampleRate);	
    var scriptNode = context.createScriptProcessor(4096, 0, 2);
    scriptNode.onaudioprocess = function(audioProcessingEvent) {
      var outputBuffer = audioProcessingEvent.outputBuffer;
      var left = outputBuffer.getChannelData(0);
      var right = outputBuffer.getChannelData(1);
        for (var sample = 0; sample < outputBuffer.length; sample++) {
        left[sample] = synth.exports["_render"]();
        right[sample] = synth.exports["_render"]();
        }
    };
    scriptNode.connect(context.destination)
  });	  
//#endif
};