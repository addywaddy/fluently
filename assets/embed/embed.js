import {startEmbed} from './widget.js'

const script = document.currentScript
if (script) startEmbed(script).catch(() => console.warn('Fluently could not initialize.'))
