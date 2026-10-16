package org.kamremake.android;

import android.content.res.AssetManager;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.List;

/** Extracts game data bundled into the APK (assets/kamdata) to the app data folder on first launch */
final class DataInstaller {
    interface Progress {
        void onProgress(long done, long total);
    }

    static final String MARKER = ".kamdata_installed";

    static boolean hasBundledData(AssetManager am) {
        try (InputStream in = am.open("kamdata.lst")) {
            return true;
        } catch (IOException e) {
            return false;
        }
    }

    static boolean isInstalled(File dir) {
        return new File(dir, MARKER).exists();
    }

    static void install(AssetManager am, File dir, Progress progress) throws IOException {
        List<String> files = new ArrayList<>();
        long total = 0;
        try (BufferedReader r = new BufferedReader(new InputStreamReader(am.open("kamdata.lst"), "UTF-8"))) {
            String line;
            while ((line = r.readLine()) != null) {
                int sp = line.indexOf(' ');
                if (sp <= 0) continue;
                total += Long.parseLong(line.substring(0, sp));
                files.add(line.substring(sp + 1));
            }
        }
        byte[] buf = new byte[1 << 20];
        long done = 0;
        for (String rel : files) {
            File out = new File(dir, rel);
            File parent = out.getParentFile();
            if (parent != null && !parent.isDirectory() && !parent.mkdirs())
                throw new IOException("Can't create " + parent);
            try (InputStream in = am.open("kamdata/" + rel); OutputStream os = new FileOutputStream(out)) {
                int n;
                while ((n = in.read(buf)) > 0) {
                    os.write(buf, 0, n);
                    done += n;
                }
            }
            progress.onProgress(done, total);
        }
        new File(dir, MARKER).createNewFile();
    }

    private DataInstaller() {}
}
