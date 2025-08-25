package app.cogwheel.conduit

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import android.os.Build
import android.os.Bundle
import androidx.core.view.WindowCompat

class MainActivity : FlutterActivity() {
    private lateinit var backgroundStreamingHandler: BackgroundStreamingHandler
    
    override fun onCreate(savedInstanceState: Bundle?) {
        // Enable edge-to-edge display for Android 15+ compatibility
        // This ensures proper handling of system bars and insets
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            // For Android 15+ (API 35), try to use enableEdgeToEdge if available
            try {
                // Use reflection to call EdgeToEdge.enable() for forward compatibility
                val edgeToEdgeClass = Class.forName("androidx.activity.EdgeToEdge")
                val enableMethod = edgeToEdgeClass.getMethod("enable", android.app.Activity::class.java)
                enableMethod.invoke(null, this)
            } catch (e: Exception) {
                // Fallback to WindowCompat if EdgeToEdge is not available
                WindowCompat.setDecorFitsSystemWindows(window, false)
            }
        } else {
            // For older versions, use WindowCompat for backward compatibility
            WindowCompat.setDecorFitsSystemWindows(window, false)
        }
        
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