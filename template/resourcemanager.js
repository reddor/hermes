//#pragma once

// leftover variables from original payload... a = byte array with image data, c = canvas
var raw = a;
var size = c.width * c.height;
var items = [];

let getByte = index => raw[index * 4];
let getInt = index => { 
	let result = 0;
	for(let i=3; i>=0; i--)
	 result = result * 0x100 + getByte(index + i);
	return result;
};

//#export
function getResourceText(index) {
	var result = "";
	for(let i=items[index]; i < items[index+1]; i++)
		result += String.fromCharCode(getByte(i));
	return result;
};

//#export
var getResourceArray = (index)=> {
	let ofs = items[index], 
	    size = items[index+1] - ofs,
	    buf = new ArrayBuffer(size),
	    result = new Uint8Array(buf);
	result.buffer = buf;
	for(let i=0; i < size;i++) 
		result[i] = getByte(i + ofs);
	return result;
};

//#export
var getResourceBlob =(index, type) => new Blob([getResourceArray(index)], {type});

//#export
var getResourceUrl = (idx, type) => window.URL.createObjectURL(getResourceBlob(idx, type));

while (getByte(size - 1) == 255) size--;
for(let i=getByte(size - 1) - 1; i>=0; i--) {
	items.push(getInt(size - (1 + (i + 1) * 4)));
}
// push end of buffer to array, minus offset table
items.push(size - (1 + items.length * 4));
