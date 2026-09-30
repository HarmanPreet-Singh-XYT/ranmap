package com.ranmap.app

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.hardware.display.DisplayManager
import android.os.SystemClock
import android.view.Display
import android.view.Surface
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import kotlin.math.abs

/**
 * Streams the device's compass heading, in degrees, to Dart over the
 * `ranmap/compass` event channel.
 *
 * This is the Android counterpart of `ios/Runner/CompassStreamHandler.swift`
 * and replaces the `flutter_compass` plugin so the app no longer depends on it.
 */
class CompassStreamHandler private constructor(
    context: Context,
) : EventChannel.StreamHandler, SensorEventListener {

    companion object {
        private const val CHANNEL = "ranmap/compass"

        // Sensor delivery rate hint (microseconds) and a throttle so we don't
        // flood Dart with sub-degree jitter; both mirror flutter_compass.
        private const val SENSOR_DELAY_MICROS = 30 * 1000
        private const val COMPASS_UPDATE_RATE_MS = 32L
        private const val ALPHA = 0.45f

        fun register(flutterEngine: FlutterEngine, context: Context) {
            val channel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            channel.setStreamHandler(CompassStreamHandler(context))
        }
    }

    private val sensorManager =
        context.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
    private val display: Display? =
        (context.getSystemService(Context.DISPLAY_SERVICE) as? DisplayManager)
            ?.getDisplay(Display.DEFAULT_DISPLAY)

    private val rotationVectorSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
    private val accelerometer = sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
    private val magneticField = sensorManager?.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD)

    private var eventSink: EventChannel.EventSink? = null
    private val truncatedRotationVector = FloatArray(4)
    private var rotationVectorValue: FloatArray? = null
    private val rotationMatrix = FloatArray(9)
    private val adjustedRotationMatrix = FloatArray(9)
    private val orientation = FloatArray(3)
    private val gravityValues = FloatArray(3)
    private val magneticValues = FloatArray(3)
    private var nextUpdateTimestamp = 0L

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        val manager = sensorManager
        val hasRotationVector = rotationVectorSensor != null
        val hasGravityAndMagnetic = accelerometer != null && magneticField != null
        if (manager == null || (!hasRotationVector && !hasGravityAndMagnetic)) {
            // No usable orientation sensors (e.g. a device without a
            // magnetometer): end the stream so Dart falls back to GPS course.
            events.endOfStream()
            return
        }
        eventSink = events
        if (hasRotationVector) {
            manager.registerListener(this, rotationVectorSensor, SENSOR_DELAY_MICROS)
        } else {
            manager.registerListener(this, accelerometer, SENSOR_DELAY_MICROS)
            manager.registerListener(this, magneticField, SENSOR_DELAY_MICROS)
        }
    }

    override fun onCancel(arguments: Any?) {
        sensorManager?.unregisterListener(this)
        eventSink = null
    }

    override fun onSensorChanged(event: SensorEvent) {
        when (event.sensor.type) {
            Sensor.TYPE_ROTATION_VECTOR -> {
                rotationVectorValue = truncatedRotationVector(event.values)
                updateHeading()
            }

            Sensor.TYPE_ACCELEROMETER -> if (rotationVectorSensor == null) {
                lowPassFilter(event.values, gravityValues)
                updateHeading()
            }

            Sensor.TYPE_MAGNETIC_FIELD -> if (rotationVectorSensor == null) {
                lowPassFilter(event.values, magneticValues)
                updateHeading()
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        // Heading is emitted regardless of reported accuracy, matching the
        // previous plugin behaviour.
    }

    private fun updateHeading() {
        val events = eventSink ?: return
        val now = SystemClock.elapsedRealtime()
        if (now < nextUpdateTimestamp) return

        val vector = rotationVectorValue
        if (vector != null) {
            SensorManager.getRotationMatrixFromVector(rotationMatrix, vector)
        } else {
            SensorManager.getRotationMatrix(rotationMatrix, null, gravityValues, magneticValues)
        }

        val rotation = display?.rotation ?: Surface.ROTATION_0

        // Assume the screen is parallel to the ground and adjust for the
        // current display rotation.
        remap(ScreenPose.FLAT, rotation)
        SensorManager.getOrientation(adjustedRotationMatrix, orientation)

        // Then refine the axis mapping depending on how the device is held —
        // each pose has its own axis table, exactly as the old plugin did.
        when {
            orientation[1] < -Math.PI / 4 -> remap(ScreenPose.TILTED_UP, rotation)
            orientation[1] > Math.PI / 4 -> remap(ScreenPose.TILTED_DOWN, rotation)
            abs(orientation[2]) > Math.PI / 2 -> remap(ScreenPose.FACE_DOWN, rotation)
        }

        SensorManager.getOrientation(adjustedRotationMatrix, orientation)
        events.success(Math.toDegrees(orientation[0].toDouble()))
        nextUpdateTimestamp = now + COMPASS_UPDATE_RATE_MS
    }

    /** How the device is held; each maps the axes differently. */
    private enum class ScreenPose { FLAT, TILTED_UP, TILTED_DOWN, FACE_DOWN }

    private fun remap(pose: ScreenPose, rotation: Int) {
        val axisX: Int
        val axisY: Int
        when (pose) {
            // Screen parallel to the ground.
            ScreenPose.FLAT -> when (rotation) {
                Surface.ROTATION_90 -> { axisX = SensorManager.AXIS_Y; axisY = SensorManager.AXIS_MINUS_X }
                Surface.ROTATION_180 -> { axisX = SensorManager.AXIS_MINUS_X; axisY = SensorManager.AXIS_MINUS_Y }
                Surface.ROTATION_270 -> { axisX = SensorManager.AXIS_MINUS_Y; axisY = SensorManager.AXIS_X }
                else -> { axisX = SensorManager.AXIS_X; axisY = SensorManager.AXIS_Y }
            }
            // Pitch below -45°: screen acts as the instrument panel.
            ScreenPose.TILTED_UP -> when (rotation) {
                Surface.ROTATION_90 -> { axisX = SensorManager.AXIS_Z; axisY = SensorManager.AXIS_MINUS_X }
                Surface.ROTATION_180 -> { axisX = SensorManager.AXIS_MINUS_X; axisY = SensorManager.AXIS_MINUS_Z }
                Surface.ROTATION_270 -> { axisX = SensorManager.AXIS_MINUS_Z; axisY = SensorManager.AXIS_X }
                else -> { axisX = SensorManager.AXIS_X; axisY = SensorManager.AXIS_Z }
            }
            // Pitch above +45°: screen upside down and facing back.
            ScreenPose.TILTED_DOWN -> when (rotation) {
                Surface.ROTATION_90 -> { axisX = SensorManager.AXIS_MINUS_Z; axisY = SensorManager.AXIS_MINUS_X }
                Surface.ROTATION_180 -> { axisX = SensorManager.AXIS_MINUS_X; axisY = SensorManager.AXIS_Z }
                Surface.ROTATION_270 -> { axisX = SensorManager.AXIS_Z; axisY = SensorManager.AXIS_X }
                else -> { axisX = SensorManager.AXIS_X; axisY = SensorManager.AXIS_MINUS_Z }
            }
            // Roll beyond ±90°: screen face down.
            ScreenPose.FACE_DOWN -> when (rotation) {
                Surface.ROTATION_90 -> { axisX = SensorManager.AXIS_MINUS_Y; axisY = SensorManager.AXIS_MINUS_X }
                Surface.ROTATION_180 -> { axisX = SensorManager.AXIS_MINUS_X; axisY = SensorManager.AXIS_Y }
                Surface.ROTATION_270 -> { axisX = SensorManager.AXIS_Y; axisY = SensorManager.AXIS_X }
                else -> { axisX = SensorManager.AXIS_X; axisY = SensorManager.AXIS_MINUS_Y }
            }
        }
        SensorManager.remapCoordinateSystem(rotationMatrix, axisX, axisY, adjustedRotationMatrix)
    }

    private fun lowPassFilter(newValues: FloatArray, smoothedValues: FloatArray) {
        for (i in smoothedValues.indices) {
            smoothedValues[i] += ALPHA * (newValues[i] - smoothedValues[i])
        }
    }

    private fun truncatedRotationVector(values: FloatArray): FloatArray {
        if (values.size <= 4) return values
        // Some devices hand back a rotation vector longer than 4 elements that
        // getRotationMatrixFromVector rejects; the first four are enough.
        System.arraycopy(values, 0, truncatedRotationVector, 0, 4)
        return truncatedRotationVector
    }
}
