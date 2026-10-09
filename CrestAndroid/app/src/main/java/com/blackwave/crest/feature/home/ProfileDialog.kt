package com.blackwave.crest.feature.home

import com.blackwave.crest.ui.localization.L
import com.blackwave.crest.ui.components.CrestDialogSystemBars

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.RectF
import android.icu.text.BreakIterator
import android.media.ExifInterface
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import com.blackwave.crest.ui.components.CrestAlertDialog as AlertDialog
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.imePadding
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.blackwave.crest.core.session.userMessage
import com.blackwave.crest.ui.components.CrestIcon
import com.blackwave.crest.ui.components.CrestIconKind
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.util.Locale
import kotlin.math.max

@Composable
internal fun ProfileDialog(
    initialDisplayName: String,
    avatarData: ByteArray?,
    onDismiss: () -> Unit,
    onSave: suspend (String) -> Unit,
    onAvatarUpload: suspend (ByteArray) -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var name by remember(initialDisplayName) { mutableStateOf(initialDisplayName) }
    var isSaving by remember { mutableStateOf(false) }
    var isUploading by remember { mutableStateOf(false) }
    var selectedBitmap by remember { mutableStateOf<Bitmap?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    val normalized = name.trim()
    val dark = MaterialTheme.colorScheme.background.luminance() < 0.5f
    val formBackground = if (dark) Color(0xFF1C1C1E) else Color(0xFFF4F3F9)
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) scope.launch {
            isUploading = true
            try {
                selectedBitmap = withContext(Dispatchers.IO) { decodeSelectedImage(context, uri) }
            } catch (failure: Exception) {
                error = failure.userMessage(L("无法读取所选图片"))
            } finally {
                isUploading = false
            }
        }
    }

    Dialog(onDismissRequest = { if (!isSaving && !isUploading) onDismiss() }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        CrestDialogSystemBars(formBackground)
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.BottomCenter) {
          Surface(
            modifier = Modifier.fillMaxWidth().fillMaxHeight(0.97f),
            shape = RoundedCornerShape(topStart = 36.dp, topEnd = 36.dp),
            color = formBackground,
          ) {
            Column(Modifier.fillMaxSize().imePadding().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(top = 16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    ProfileToolbarButton(CrestIconKind.CLOSE, L("取消"), enabled = !isSaving && !isUploading, onClick = onDismiss)
                    Text(L("个人资料"), fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
                    ProfileToolbarButton(
                        CrestIconKind.CHECK,
                        L("保存"),
                        enabled = characterCount(normalized) in 1..30 && !isSaving && !isUploading,
                        tint = MaterialTheme.colorScheme.secondary,
                    ) {
                        scope.launch {
                            isSaving = true
                            try {
                                onSave(normalized)
                                onDismiss()
                            } catch (failure: Exception) {
                                error = failure.userMessage(L("昵称修改失败"))
                            } finally {
                                isSaving = false
                            }
                        }
                    }
                }
                Column(
                    Modifier.fillMaxWidth().padding(top = 68.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    AccountAvatar(avatarData, initialDisplayName.take(1).uppercase(), 96.dp)
                    if (isUploading) CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp)
                    else TextButton(onClick = {
                        picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                    }) {
                        CrestIcon(CrestIconKind.IMAGE, Modifier.size(21.dp), MaterialTheme.colorScheme.secondary)
                        Text("  " + L("修改头像"), color = MaterialTheme.colorScheme.secondary)
                    }
                }
                Text(
                    L("昵称"),
                    modifier = Modifier.padding(start = 12.dp, top = 36.dp, bottom = 10.dp),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    fontSize = 14.sp,
                )
                BasicTextField(
                    value = name,
                    onValueChange = { name = it },
                    singleLine = true,
                    textStyle = MaterialTheme.typography.bodyLarge.copy(color = MaterialTheme.colorScheme.onSurface),
                    modifier = Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surface, RoundedCornerShape(22.dp))
                        .padding(horizontal = 16.dp, vertical = 15.dp),
                    decorationBox = { inner ->
                        Box {
                            if (name.isEmpty()) Text(L("输入昵称"), color = MaterialTheme.colorScheme.onSurfaceVariant)
                            inner()
                        }
                    },
                )
                Text(
                    L("昵称为 1 至 30 个字符"),
                    modifier = Modifier.padding(start = 12.dp, top = 8.dp),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    fontSize = 12.sp,
                )
            }
          }
        }
    }

    selectedBitmap?.let { bitmap ->
        AvatarCropDialog(
            bitmap = bitmap,
            onDismiss = { selectedBitmap = null },
            onConfirm = { bytes ->
                selectedBitmap = null
                scope.launch {
                    isUploading = true
                    try {
                        onAvatarUpload(bytes)
                    } catch (failure: Exception) {
                        error = failure.userMessage(L("头像上传失败"))
                    } finally {
                        isUploading = false
                    }
                }
            },
            onError = { error = it },
        )
    }
    error?.let { message ->
        AlertDialog(
            onDismissRequest = { error = null },
            title = { Text(L("个人资料修改失败")) },
            text = { Text(message) },
            confirmButton = { TextButton(onClick = { error = null }) { Text(L("好")) } },
        )
    }
}

private fun characterCount(value: String): Int {
    val iterator = BreakIterator.getCharacterInstance(Locale.getDefault())
    iterator.setText(value)
    var count = 0
    while (iterator.next() != BreakIterator.DONE) count++
    return count
}

@Composable
private fun ProfileToolbarButton(
    icon: CrestIconKind,
    label: String,
    enabled: Boolean,
    tint: Color = MaterialTheme.colorScheme.onSurface,
    onClick: () -> Unit,
) {
    Surface(
        onClick = onClick,
        enabled = enabled,
        modifier = Modifier.size(40.dp).semantics { contentDescription = label },
        shape = CircleShape,
        color = MaterialTheme.colorScheme.surface,
    ) {
        Box(contentAlignment = Alignment.Center) {
            CrestIcon(icon, Modifier.size(19.dp), tint.copy(alpha = if (enabled) 1f else 0.35f))
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AvatarCropDialog(
    bitmap: Bitmap,
    onDismiss: () -> Unit,
    onConfirm: (ByteArray) -> Unit,
    onError: (String) -> Unit,
) {
    var zoom by remember { mutableStateOf(1f) }
    var offset by remember { mutableStateOf(Offset.Zero) }
    val density = LocalDensity.current
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(modifier = Modifier.fillMaxSize(), color = Color.Black) {
            BoxWithConstraints(Modifier.fillMaxSize()) {
                val cropSize = minOf(maxWidth - 32.dp, maxHeight - 180.dp)
                val cropPixels = with(density) { cropSize.toPx() }
                fun clamp(candidate: Offset, currentZoom: Float): Offset {
                    val base = max(cropPixels / bitmap.width, cropPixels / bitmap.height) * currentZoom
                    val xLimit = max(0f, (bitmap.width * base - cropPixels) / 2f)
                    val yLimit = max(0f, (bitmap.height * base - cropPixels) / 2f)
                    return Offset(candidate.x.coerceIn(-xLimit, xLimit), candidate.y.coerceIn(-yLimit, yLimit))
                }
                Column(Modifier.fillMaxSize().padding(top = 26.dp, bottom = 36.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Row(
                        Modifier.fillMaxWidth().padding(horizontal = 20.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        TextButton(onClick = onDismiss) { Text(L("取消"), color = Color.White) }
                        Text(L("调整头像"), color = Color.White, fontWeight = FontWeight.SemiBold)
                        TextButton(onClick = {
                            val result = cropAvatar(bitmap, zoom, offset, cropPixels)
                            if (result == null) onError(L("无法处理所选图片")) else onConfirm(result)
                        }) { Text(L("使用"), color = Color.White) }
                    }
                    Spacer(Modifier.weight(1f))
                    Box(
                        Modifier.size(cropSize).clip(CircleShape)
                            .border(1.dp, Color.White.copy(alpha = 0.9f), CircleShape)
                            .pointerInput(bitmap, cropPixels) {
                                detectTransformGestures { _, pan, scale, _ ->
                                    zoom = (zoom * scale).coerceIn(1f, 4f)
                                    offset = clamp(offset + pan, zoom)
                                }
                            },
                    ) {
                        Image(
                            bitmap = bitmap.asImageBitmap(),
                            contentDescription = L("头像裁剪预览"),
                            contentScale = ContentScale.Crop,
                            modifier = Modifier.fillMaxSize().graphicsLayer {
                                scaleX = zoom
                                scaleY = zoom
                                translationX = offset.x
                                translationY = offset.y
                            },
                        )
                    }
                    Row(
                        Modifier.fillMaxWidth().padding(horizontal = 26.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text("−", color = Color.White, fontSize = 20.sp)
                        Slider(
                            value = zoom,
                            onValueChange = { zoom = it; offset = clamp(offset, zoom) },
                            valueRange = 1f..4f,
                            modifier = Modifier.weight(1f).padding(horizontal = 10.dp),
                            colors = SliderDefaults.colors(
                                thumbColor = Color.White,
                                activeTrackColor = Color.White,
                                inactiveTrackColor = Color(0xFF303033),
                            ),
                            thumb = { Box(Modifier.size(22.dp).background(Color.White, RoundedCornerShape(7.dp))) },
                        )
                        Text("+", color = Color.White, fontSize = 20.sp)
                    }
                    Spacer(Modifier.weight(1f))
                }
            }
        }
    }
}

private fun decodeSelectedImage(context: Context, uri: Uri): Bitmap {
    val resolver = context.contentResolver
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
    require(bounds.outWidth > 0 && bounds.outHeight > 0) { L("无法读取所选图片") }
    val sample = generateSequence(1) { it * 2 }.first {
        max(bounds.outWidth, bounds.outHeight) / it <= 2048
    }
    val options = BitmapFactory.Options().apply { inSampleSize = sample }
    val bitmap = resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, options) }
        ?: throw IllegalArgumentException(L("无法读取所选图片"))
    val orientation = resolver.openInputStream(uri)?.use { ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL) }
    val transform = Matrix().apply {
        when (orientation) {
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> setScale(-1f, 1f)
            ExifInterface.ORIENTATION_ROTATE_180 -> setRotate(180f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> setScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> { setRotate(90f); postScale(-1f, 1f) }
            ExifInterface.ORIENTATION_ROTATE_90 -> setRotate(90f)
            ExifInterface.ORIENTATION_TRANSVERSE -> { setRotate(270f); postScale(-1f, 1f) }
            ExifInterface.ORIENTATION_ROTATE_270 -> setRotate(270f)
        }
    }
    return if (transform.isIdentity) bitmap else Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, transform, true)
}

private fun cropAvatar(bitmap: Bitmap, zoom: Float, offset: Offset, viewportPixels: Float): ByteArray? {
    if (viewportPixels <= 0f) return null
    val output = Bitmap.createBitmap(512, 512, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(output)
    canvas.drawColor(android.graphics.Color.BLACK)
    val scale = max(512f / bitmap.width, 512f / bitmap.height) * zoom
    val width = bitmap.width * scale
    val height = bitmap.height * scale
    val dx = offset.x / viewportPixels * 512f
    val dy = offset.y / viewportPixels * 512f
    canvas.drawBitmap(bitmap, null, RectF((512 - width) / 2f + dx, (512 - height) / 2f + dy, (512 + width) / 2f + dx, (512 + height) / 2f + dy), Paint(Paint.FILTER_BITMAP_FLAG))
    for (quality in listOf(82, 68, 52)) {
        val stream = ByteArrayOutputStream()
        if (output.compress(Bitmap.CompressFormat.JPEG, quality, stream) && stream.size() <= 1024 * 1024) return stream.toByteArray()
    }
    return null
}
