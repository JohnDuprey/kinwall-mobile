import { registerRootComponent } from 'expo'
import './src/routineBackground'
import App from './src/App'
import { registerWidgets } from './src/widgets'

registerRootComponent(App)
registerWidgets() // Android: the home-screen widget's headless renderer
