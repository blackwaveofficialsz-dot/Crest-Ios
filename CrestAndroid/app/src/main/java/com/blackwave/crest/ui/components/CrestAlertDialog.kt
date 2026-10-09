package com.blackwave.crest.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog

/** Shared layout for iOS-style confirmation, rename and account notices. */
@Composable
fun CrestAlertDialog(
    onDismissRequest: () -> Unit,
    confirmButton: @Composable () -> Unit,
    title: @Composable () -> Unit,
    text: @Composable () -> Unit,
    dismissButton: (@Composable () -> Unit)? = null,
    shape: Shape = RoundedCornerShape(28.dp),
    containerColor: Color = MaterialTheme.colorScheme.surface,
    tonalElevation: Dp = 0.dp,
) {
    Dialog(onDismissRequest = onDismissRequest) {
        Surface(
            modifier = Modifier.widthIn(max = 320.dp).fillMaxWidth(), shape = shape,
            color = containerColor, tonalElevation = tonalElevation, shadowElevation = 20.dp,
            border = BorderStroke(0.7.dp, Brush.verticalGradient(listOf(Color.White.copy(alpha = .32f), MaterialTheme.colorScheme.outline.copy(alpha = .45f)))),
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Column(Modifier.fillMaxWidth().padding(horizontal = 22.dp, vertical = 22.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(9.dp)) {
                    ProvideTextStyle(MaterialTheme.typography.titleMedium.copy(fontSize = 17.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)) { title() }
                    ProvideTextStyle(MaterialTheme.typography.bodySmall.copy(fontSize = 13.sp, textAlign = TextAlign.Center)) { text() }
                }
                HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = .55f))
                MaterialTheme(colorScheme = MaterialTheme.colorScheme.copy(primary = MaterialTheme.colorScheme.secondary)) {
                  Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min)) {
                    if (dismissButton != null) {
                        Box(Modifier.weight(1f).height(50.dp), contentAlignment = Alignment.Center, propagateMinConstraints = true) { dismissButton() }
                        VerticalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = .55f))
                    }
                    Box(Modifier.weight(1f).height(50.dp), contentAlignment = Alignment.Center, propagateMinConstraints = true) { confirmButton() }
                  }
                }
            }
        }
    }
}
