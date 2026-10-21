package com.viraltia.teleprompt

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.createSavedStateHandle
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.viraltia.teleprompt.ui.AppViewModel
import com.viraltia.teleprompt.ui.TelepromptApp

class MainActivity : ComponentActivity() {
    private lateinit var model: AppViewModel
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        model = ViewModelProvider(this, viewModelFactory {
            initializer { AppViewModel(application as TelepromptApplication, createSavedStateHandle()) }
        })[AppViewModel::class.java]
        setContent { TelepromptApp(model, this) }
    }
    override fun onStart() { super.onStart(); (application as TelepromptApplication).access.refresh() }
    override fun onStop() { model.flushDraft(); super.onStop() }
}
