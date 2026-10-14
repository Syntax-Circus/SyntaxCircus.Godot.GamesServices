package com.syntaxcircus.godot.gamesservices

import com.android.manifmerger.ManifestMerger2
import com.android.manifmerger.MergingReport
import com.android.utils.StdLogger
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.util.zip.ZipFile
import javax.xml.parsers.DocumentBuilderFactory

class StartupManifestTest {
    @Test fun sdkDependencyCannotInitializeOrCreateProfileBeforeConsent() {
        val directory = kotlin.io.path.createTempDirectory("games-manifest-").toFile()
        try {
            val sdkManifest = File(directory, "sdk.xml")
            ZipFile(System.getProperty("gamesSdkAar")).use { zip ->
                sdkManifest.writeBytes(zip.getInputStream(zip.getEntry("AndroidManifest.xml")).readBytes())
            }
            val plugin = File(directory, "plugin.xml")
            ZipFile(File("build/outputs/aar/plugin-debug.aar")).use { zip ->
                plugin.writeBytes(zip.getInputStream(zip.getEntry("AndroidManifest.xml")).readBytes())
            }
            val app = File(directory, "app.xml")
            app.writeText("""<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="test.optin"><uses-sdk android:minSdkVersion="24"/><application/></manifest>""")
            val report = ManifestMerger2.newMerger(app, StdLogger(StdLogger.Level.ERROR), ManifestMerger2.MergeType.APPLICATION)
                .withFeatures(ManifestMerger2.Invoker.Feature.REMOVE_TOOLS_DECLARATIONS)
                .addLibraryManifest(plugin)
                .addLibraryManifest(sdkManifest)
                .merge()
            assertFalse(report.loggingRecords.joinToString("\n") { it.toString() }, report.result.isError)
            val merged = report.getMergedDocument(MergingReport.MergedManifestKind.MERGED)!!
            val factory = DocumentBuilderFactory.newInstance().apply { isNamespaceAware = true }
            val document = factory.newDocumentBuilder().parse(merged.byteInputStream())
            val android = "http://schemas.android.com/apk/res/android"
            val providers = document.getElementsByTagName("provider")
            for (index in 0 until providers.length) {
                assertFalse("SDK startup provider must be removed before consent: " + merged,
                    providers.item(index).attributes.getNamedItemNS(android, "name")?.nodeValue?.endsWith("PlayGamesInitProvider") == true)
            }
            val metadata = document.getElementsByTagName("meta-data")
            val suppression = (0 until metadata.length).map { metadata.item(it) }.singleOrNull {
                it.attributes.getNamedItemNS(android, "name")?.nodeValue == "com.google.android.gms.games.SUPPRESS_GAME_PROFILE_CREATION"
            }
            assertNotNull("Profile creation must be suppressed", suppression)
            assertEquals("true", suppression!!.attributes.getNamedItemNS(android, "value").nodeValue)
        } finally {
            directory.deleteRecursively()
        }
    }
}
