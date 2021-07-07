(function() {

if (!(window.webkit
  && window.webkit.messageHandlers
  && window.webkit.messageHandlers.webMidiBrowser
  )) {
  throw new Error('missing required WKWebView integration');
}

function stringify(obj, replacer, spaces, cycleReplacer) {
  return JSON.stringify(obj, serializer(replacer, cycleReplacer), spaces)
}

function serializer(replacer, cycleReplacer) {
  var stack = [], keys = []

  if (cycleReplacer == null) cycleReplacer = function(key, value) {
    if (stack[0] === value) return "[Circular ~]"
    return "[Circular ~." + keys.slice(0, stack.indexOf(value)).join(".") + "]"
  }

  return function(key, value) {
    if (stack.length > 0) {
      var thisPos = stack.indexOf(this)
      ~thisPos ? stack.splice(thisPos + 1) : stack.push(this)
      ~thisPos ? keys.splice(thisPos, Infinity, key) : keys.push(key)
      if (~stack.indexOf(value)) value = cycleReplacer.call(this, key, value)
    }
    else stack.push(value)

    return replacer == null ? value : replacer.call(this, key, value)
  }
}

function log(...args) {
  window.webkit.messageHandlers.webMidiBrowser.postMessage({
    type: 'log',
    value: args.map(v => typeof v === 'string' ? v : stringify(v)).join(' ')
  })
}

function logError(error, extra) {
  log('error:', stringify({name:error.name, message:error.message, stack: error.stack, extra}))
}

window.onerror = logError;
console.log = log;
console.warn = log;
console.error = function error(...args) {
  log(...args, new Error('stack').stack)
}
 

class MIDIMessageEvent extends Event {
    constructor(receivedTime, data) {
        super("midimessage");
        this.receivedTime = receivedTime;
        this.data = data;
    }
}

class MIDIConnectionEvent extends Event {
    constructor(port) {
        super("midiconnection");
        this.port = port;
    }
}

class MIDIPort {
  constructor(properties) {
    this._setProperties(properties, true)
  }
  _setProperties({

     /*DOMString               */id,
     /*DOMString?              */manufacturer,
     /*DOMString?              */name,
     /*MIDIPortType            */type,
     /*DOMString?              */version,
     /*MIDIPortDeviceState     */state,
     /*MIDIPortConnectionState */connection,
  }, isNewPort = false) { 
    const stateChange = state !== this.state || connection !== this.connection;
    this._stateChangeEvent = null
    Object.assign(this, {
      id,
      manufacturer,
      name,
      type,
      version,
      state,
      connection,
    });
    if (stateChange || isNewPort) {
      // expose event so it can be emitted to access-level subscriber
      this._stateChangeEvent = new MIDIConnectionEvent(this)
      // emit state change to direct subscriber on port
      if (this.onstatechange) {
        this.onstatechange(this._stateChangeEvent)
      }
    } 
  }
  open () {
    return Promise.resolve(this);
  }
  close () {
    return Promise.resolve(this);
  }
}


class MIDIOutput extends MIDIPort {
  // Enqueues the message to be sent to the corresponding MIDI port
  send(message) {
    window.webkit.messageHandlers.webMidiBrowser.postMessage({
      type: 'midioutput',
      portID: this.id,
      data: Array.from(message),
    }) 
  }
  // Clears any pending send data that has not yet been sent from the MIDIOutput's queue
  clear () {
    // not implemented
  }
}
class MIDIInput extends MIDIPort {
  // attribute EventHandler onmidimessage;
}



var MIDIInputs = new Map()
var MIDIOutputs = new Map()
var accessObjects = []

function forEachPortByType(type, cb)  { 
  accessObjects.forEach(access => {
    (type === 'input' ? access.inputs : access.outputs).forEach(port => cb(port, access))
  })
}
function forEachOutput(cb)  { 
  accessObjects.forEach(access => {
    access.outputs.forEach(cb)
  })
}

var sysexEnabled = false;

function onMIDIMessage({portID, data}) { 
 const event = new MIDIMessageEvent(performance.now(), data)
  forEachPortByType('input', (port) => {
    if (port.id === portID && port.onmidimessage) {
      port.onmidimessage(event);
    }
  })
}

function onStateChange({properties}) { 
  
  const map = properties.type=='input'?MIDIInputs:MIDIOutputs;

  if (map.has(properties.id)) { 
    accessObjects.forEach(access => {
      const accessMap = properties.type=='input'?access.inputs:access.outputs;
      const accessPort = accessMap.get(properties.id)
      accessPort._setProperties(properties);
      if (accessPort._stateChangeEvent && access.onstatechange) {
        access.onstatechange(accessPort._stateChangeEvent);
      }
    })  

  } else { 
    // add to global list
    const newPort = (properties.type=='input'? new MIDIInput(properties):new MIDIOutput(properties));
    map.set(properties.id, newPort);
    log('created new port', newPort)

    // add a copy to each midiaccess object
    accessObjects.forEach(access => {
      const accessMap = properties.type=='input'?access.inputs:access.outputs;
      const accessPort = (properties.type=='input'? new MIDIInput(properties):new MIDIOutput(properties));
      accessMap.set(properties.id, accessPort);
      log('created new port at access level', accessPort, access.__id);


      // emit change at access level
      if (accessPort._stateChangeEvent && access.onstatechange) {
        log('emitting change to access', access.__id)
        access.onstatechange(accessPort._stateChangeEvent);
      }
    })
  }
}



function connectToHostApp() {
  window.webkit.messageHandlers.webMidiBrowser.postMessage({
    type: 'connect',
  })
}

var HostAppAPI = {
  receiveMessage(json) {
    try {
      const parsed = JSON.parse(json);
      switch (parsed.type) {
        case 'midimessage':
          return onMIDIMessage(parsed);
        case 'statechange':
          return onStateChange(parsed);
        default:
          throw new Error('unknown message type: '+parsed.type);
      }
    } catch (err) {
      logError(err, {json, caughtAt: 'receiveMessage error'})  
    }
  }
}

window.__WebMidiBrowser = HostAppAPI;

let accessID = 0;

navigator.requestMIDIAccess = function requestMIDIAccess() {
    log('requestMIDIAccess', accessID);
    const access = {
      __id: accessID++,
      inputs: new Map(Array.from(MIDIInputs).map(([id,input]) => new MIDIInput(input))),
      outputs: new Map(Array.from(MIDIOutputs).map(([id,output]) => new MIDIOutput(output))),
    }
    accessObjects.push(access);


    return Promise.resolve(access)
}

connectToHostApp();
})()