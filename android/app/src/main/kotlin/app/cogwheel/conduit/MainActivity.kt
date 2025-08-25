package app.cogwheel.conduit

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import android.os.Bundle
import androidx.core.view.WindowCompat

class MainActivity : FlutterActivity() {
    private lateinit var backgroundStreamingHandler: BackgroundStreamingHandler
    
    override fun onCreate(savedInstanceState: Bundle?) {
        // Enable edge-to-edge display for Android 15+ compatibility
        WindowCompat.setDecorFitsSystemWindows(window, false)
        super.onCreate(savedInstanceState)
    }
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Initialize background streaming handler
        backgroundStreamingHandler = BackgroundStreamingHandler(this)
        backgroundStreamingHandler.setup(flutterEngine)
    }
    
    override fun onDestroy() {
        super.onDestroy()
        if (::backgroundStreamingHandler.isInitialized) {
            backgroundStreamingHandler.cleanup()
        }
    }
}