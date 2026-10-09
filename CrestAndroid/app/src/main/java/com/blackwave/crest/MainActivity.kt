package com.blackwave.crest

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.blackwave.crest.ui.localization.AppLocalization

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        AppLocalization.initialize(this)
        enableEdgeToEdge()
        setContent { CrestApp() }
    }
}
