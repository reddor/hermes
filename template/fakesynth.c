#include <emscripten.h>
#include <math.h>


// batantly borrowed from https://playground.arduino.cc/Main/RickRoll/
#define  a3f    208     // 208 Hz
#define  b3f    233     // 233 Hz
#define  b3     247     // 247 Hz
#define  c4     261     // 261 Hz MIDDLE C
#define  c4s    277     // 277 Hz
#define  e4f    311     // 311 Hz    
#define  f4     349     // 349 Hz 
#define  a4f    415     // 415 Hz  
#define  b4f    466     // 466 Hz 
#define  b4     493     // 493 Hz 
#define  c5     523     // 523 Hz 
#define  c5s    554     // 554 Hz
#define  e5f    622     // 622 Hz  
#define  f5     698     // 698 Hz 
#define  f5s    740     // 740 Hz
#define  a5f    831     // 831 Hz 
#define rest    -1

int song1_chorus_melody[] =
{ b4f, b4f, a4f, a4f,
  f5, f5, e5f, b4f, b4f, a4f, a4f, e5f, e5f, c5s, c5, b4f,
  c5s, c5s, c5s, c5s,
  c5s, e5f, c5, b4f, a4f, a4f, a4f, e5f, c5s,
  b4f, b4f, a4f, a4f,
  f5, f5, e5f, b4f, b4f, a4f, a4f, a5f, c5, c5s, c5, b4f,
  c5s, c5s, c5s, c5s,
  c5s, e5f, c5, b4f, a4f, rest, a4f, e5f, c5s, rest
};

int ticks;
int samplerate;
int channel;
int p;
float pos;
float currentFreq;

void melody() {
    p++;
    if(p>sizeof(song1_chorus_melody)/sizeof(int)) {
        p = 0;
    }
    if(song1_chorus_melody[p]<0)
        currentFreq = 0;
    else
    {
        currentFreq = 2.f * 3.1415926f * song1_chorus_melody[p] / samplerate;
        pos = -currentFreq;
    }
    
}
EMSCRIPTEN_KEEPALIVE float render() {
    channel = (channel + 1) % 2;
    int noteLength = samplerate / 3;

    if (!channel) {
        ticks++;
        if (!(ticks % noteLength)) {
            melody();
        }
        pos += currentFreq;
        if (pos> 3.1415926f) pos -= 2 * 3.1415926f;
    }
    float vol = 1.f - (ticks % noteLength) / (float)noteLength;
    if (currentFreq == 0) {
        return 0.0f;
    }
    return sinf(pos) * 0.2f * vol * vol;
}

EMSCRIPTEN_KEEPALIVE void initializeSynth(int sr) {
	ticks = 0;
    samplerate = sr;
    pos = 0;
}
	
