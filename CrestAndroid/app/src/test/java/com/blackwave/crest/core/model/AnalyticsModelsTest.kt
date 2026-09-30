package com.blackwave.crest.core.model

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AnalyticsModelsTest {
    private val json = Json { ignoreUnknownKeys = true; explicitNulls = false }

    @Test
    fun decodesOverviewWithMetricsAndDimensions() {
        val overview = json.decodeFromString<AnalyticsOverview>(
            """
            {
              "period": {"date_from": "2026-09-01", "date_to": "2026-09-29"},
              "metrics": {
                "net_income": {"current": 12880.5, "previous": 11200, "change_rate": 0.15}
              },
              "channels": [
                {
                  "dim_key": "delivery",
                  "dim_label": "外卖",
                  "metrics": {"order_count": {"current": 96}}
                }
              ],
              "generated_at": "2026-09-30T08:00:00Z"
            }
            """.trimIndent(),
        )

        assertEquals("2026-09-01", overview.period.dateFrom)
        assertEquals(12880.5, overview.metrics.getValue("net_income").current!!, 0.001)
        assertEquals("delivery", overview.channels.single().id)
        assertEquals("外卖", overview.channels.single().label)
        assertEquals(96.0, overview.channels.single().metrics.getValue("order_count").current!!, 0.001)
        assertNull(overview.previousPeriod)
    }
}
