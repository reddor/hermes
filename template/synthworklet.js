class wasmsynth extends AudioWorkletProcessor {
    constructor() {
        super();
        this.port.onmessage = (e) => {
            if(e.data.t == "init")
                this.init(e.data.b, e.data.sr);
        };
    }
    process(inputs, outputs, parameters) {
        if(this.synth) {
            let l = outputs[0][0];
            let r = outputs[0][1];
            for(let i=0; i < l.length;i++) {
                l[i] = this.synth.exports["_render"]();
                r[i] = this.synth.exports["_render"]();
            }
        }
        return true;
    }
    init(b, sr) {
        if(this.importObject) return;
        this.importObject = {
            'env': {
                '__memory_base': 0,
                '__table_base': 0,
                'memory': new WebAssembly.Memory({initial: 8192}),
                'table': new WebAssembly.Table({initial: 8192, element: 'anyfunc'}) ,
                'abort': (e) =>null,
                '_cosf': Math.cos,
                '_sinf': Math.sin,
                '_llvm_exp2_f32': (x, y) => y ? x * Math.pow(2, y) : Math.pow(2, x),
                }	 
        }; 
        WebAssembly.instantiate(b, this.importObject).then(r => {
            this.synth = r.instance;
            this.synth.exports["__post_instantiate"]();
            this.synth.exports["_initializeSynth"](sr);
        });	    
    }
}
registerProcessor('wasmsynth', wasmsynth);
