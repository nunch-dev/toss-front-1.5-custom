package org.plf02wh.featureprobe;

import android.Manifest;
import android.app.Activity;
import android.app.DownloadManager;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.database.Cursor;
import android.net.Uri;
import android.os.Bundle;
import android.os.Environment;
import android.os.ParcelFileDescriptor;
import android.provider.ContactsContract;
import android.provider.OpenableColumns;
import android.text.Editable;
import android.text.InputType;
import android.text.SpanWatcher;
import android.text.Spannable;
import android.text.Spanned;
import android.text.TextWatcher;
import android.view.Gravity;
import android.view.View;
import android.view.inputmethod.BaseInputConnection;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Locale;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class MainActivity extends Activity {
    private static final int CREATE = 10;
    private static final int OPEN = 11;
    private static final int CONTACTS = 12;
    private static final String PREFIX = "plf02wh-test-";
    private static final byte[] MARKER =
            "PLF02WH_FEATURE_PROBE_V1\n".getBytes(StandardCharsets.UTF_8);
    private final ExecutorService io = Executors.newSingleThreadExecutor();
    private SharedPreferences prefs;
    private LinearLayout layout;
    private TextView imeStatus;
    private TextView safStatus;
    private TextView downloadStatus;
    private TextView contactsStatus;
    private TextView ownership;
    private EditText ime;
    private EditText url;
    private String pendingName;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        prefs = getSharedPreferences("probe", MODE_PRIVATE);
        pendingName = state == null ? null : state.getString("pendingName");
        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        int padding = (int) (16 * getResources().getDisplayMetrics().density);
        layout.setPadding(padding, padding, padding, padding);
        scroll.addView(layout);
        setContentView(scroll);
        text("PLF02WH Feature Probe\nManual QA only. No automatic permission grants.", 20);
        text("1. Korean IME: type real text below", 18);
        ime = new EditText(this);
        ime.setId(100);
        ime.setGravity(Gravity.TOP | Gravity.START);
        ime.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_MULTI_LINE);
        ime.setMinLines(3);
        ime.setHint("Type Korean with the selected IME");
        layout.addView(ime, fullWidth());
        imeStatus = text("IME: no input", 14);
        ime.addTextChangedListener(new TextWatcher() {
            public void beforeTextChanged(CharSequence s, int start, int count, int after) {}
            public void onTextChanged(CharSequence s, int start, int before, int count) {}
            public void afterTextChanged(Editable s) { scheduleImeStatus(); }
        });
        ime.getText().setSpan(new SpanWatcher() {
            public void onSpanAdded(Spannable s, Object what, int start, int end) {
                scheduleImeStatus();
            }
            public void onSpanRemoved(Spannable s, Object what, int start, int end) {
                scheduleImeStatus();
            }
            public void onSpanChanged(Spannable s, Object what, int os, int oe, int ns, int ne) {
                scheduleImeStatus();
            }
        }, 0, ime.length(), Spanned.SPAN_INCLUSIVE_INCLUSIVE);
        button("Refresh real IME state", v -> showImeStatus());
        text("2. SAF fixed marker test", 18);
        button("Create new marker document", v -> {
            pendingName = PREFIX + UUID.randomUUID() + ".txt";
            Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT)
                    .addCategory(Intent.CATEGORY_OPENABLE).setType("text/plain")
                    .putExtra(Intent.EXTRA_TITLE, pendingName);
            safStatus.setText("CREATE picker: requested name=" + pendingName
                    + "\nKeep this exact name. A changed name will not be written.");
            launchPicker(intent, CREATE);
        });
        button("Open selected test document", v -> launchPicker(
                new Intent(Intent.ACTION_OPEN_DOCUMENT)
                        .addCategory(Intent.CATEGORY_OPENABLE).setType("text/plain"), OPEN));
        safStatus = text("SAF: not run", 14);
        text("3. DownloadManager", 18);
        url = new EditText(this);
        url.setId(101);
        url.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_URI);
        url.setText("http://127.0.0.1:8765/plf02wh-download.txt");
        layout.addView(url, fullWidth());
        button("Enqueue owned Downloads file", v -> enqueue());
        button("Query actual downloads and hashes", v -> runIo(downloadStatus, this::queryDownloads));
        downloadStatus = text("DownloadManager: not queried", 14);
        text("4. Contacts permission and API", 18);
        button("Request READ_CONTACTS", v -> {
            contactsStatus.setText("READ_CONTACTS request started; provider NOT queried.");
            requestPermissions(new String[] { Manifest.permission.READ_CONTACTS }, CONTACTS);
        });
        button("Query contacts API (count only)", v -> runIo(contactsStatus, this::queryContacts));
        contactsStatus = text("READ_CONTACTS=" + permissionState() + "; API not queried", 14);
        text("Owned artifacts (persistent cleanup ledger)", 18);
        ownership = text(prefs.getString("ledger", "No artifacts created."), 14);
        text("Remove only the exact listed SAF URIs/files and DownloadManager IDs/files. "
                + "The app never deletes documents or contacts.", 14);
    }

    private LinearLayout.LayoutParams fullWidth() {
        return new LinearLayout.LayoutParams(-1, -2);
    }

    private TextView text(String value, int size) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(size);
        view.setTextIsSelectable(true);
        view.setPadding(0, 8, 0, 8);
        layout.addView(view, fullWidth());
        return view;
    }

    private void button(String label, View.OnClickListener listener) {
        Button button = new Button(this);
        button.setText(label);
        button.setAllCaps(false);
        button.setOnClickListener(listener);
        layout.addView(button, fullWidth());
    }

    private void scheduleImeStatus() {
        imeStatus.removeCallbacks(imeUpdate);
        imeStatus.post(imeUpdate);
    }

    private final Runnable imeUpdate = this::showImeStatus;

    private void showImeStatus() {
        Editable value = ime.getText();
        imeStatus.setText("UTF-16 length=" + value.length()
                + "; selection=" + ime.getSelectionStart() + ".." + ime.getSelectionEnd()
                + "; composing=" + BaseInputConnection.getComposingSpanStart(value)
                + ".." + BaseInputConnection.getComposingSpanEnd(value)
                + "\nText=[" + value + "]");
    }

    private void launchPicker(Intent intent, int code) {
        try {
            startActivityForResult(intent, code);
        } catch (RuntimeException e) {
            safStatus.setText("Picker ERROR=" + e.getClass().getSimpleName());
        }
    }

    @Override protected void onActivityResult(int request, int result, Intent data) {
        super.onActivityResult(request, result, data);
        if (request != CREATE && request != OPEN) return;
        if (result != RESULT_OK || data == null || data.getData() == null) {
            safStatus.setText("SAF CANCELLED: no file opened or written.");
            return;
        }
        Uri uri = data.getData();
        String expected = pendingName;
        // Record every newly created URI, including an empty file rejected below.
        if (request == CREATE) record("SAF CREATED URI=" + uri + "; requested=" + expected);
        runIo(safStatus, () -> {
            String name;
            try (Cursor cursor = getContentResolver().query(uri,
                    new String[] { OpenableColumns.DISPLAY_NAME }, null, null, null)) {
                if (cursor == null || !cursor.moveToFirst()) {
                    return "SAF ERROR: display name unavailable; no content accessed.\nURI=" + uri;
                }
                name = cursor.getString(0);
            }
            String identity = "name=" + name + "\nURI=" + uri;
            if (request == CREATE) record("SAF CREATED " + identity);
            if (name == null || !name.startsWith(PREFIX)
                    || (request == CREATE && !name.equals(expected))) {
                return "SAF REJECTED: test filename mismatch; no content accessed.\n" + identity;
            }
            if (request == CREATE) {
                try (OutputStream stream = getContentResolver().openOutputStream(uri, "w")) {
                    if (stream == null) return "SAF WRITE ERROR: null stream\n" + identity;
                    stream.write(MARKER);
                }
                return "SAF WRITE OK; bytes=" + MARKER.length
                        + "; SHA256=" + hex(MessageDigest.getInstance("SHA-256").digest(MARKER))
                        + "\n" + identity;
            }
            try (InputStream stream = getContentResolver().openInputStream(uri)) {
                if (stream == null) return "SAF READ ERROR: null stream\n" + identity;
                return "SAF READ " + digest(stream, true) + "\n" + identity;
            }
        });
    }

    private void enqueue() {
        try {
            Uri source = Uri.parse(url.getText().toString().trim());
            String scheme = source.getScheme();
            if (source.getHost() == null || !("http".equals(scheme) || "https".equals(scheme))
                    || source.getUserInfo() != null
                    || ("http".equals(scheme) && !"127.0.0.1".equals(source.getHost()))) {
                downloadStatus.setText("URL REJECTED: HTTPS or HTTP host 127.0.0.1 only; no credentials.");
                return;
            }
            String name = PREFIX + "download-" + UUID.randomUUID() + ".txt";
            DownloadManager manager = getSystemService(DownloadManager.class);
            long id = manager.enqueue(new DownloadManager.Request(source)
                    .setTitle(name)
                    .setDescription("PLF02WH diagnostic fixture")
                    .setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, name));
            String entry = "DownloadManager ID=" + id + "; Downloads/" + name
                    + "; URI=content://downloads/my_downloads/" + id;
            String ids = prefs.getString("downloadIds", "").trim();
            prefs.edit().putString("downloadIds", ids.isEmpty() ? Long.toString(id) : ids + " " + id).commit();
            record(entry);
            downloadStatus.setText("ENQUEUED ONLY; completion not yet checked.\n" + entry);
        } catch (RuntimeException e) {
            downloadStatus.setText("ENQUEUE ERROR=" + e.getClass().getSimpleName());
        }
    }

    private String queryDownloads() throws Exception {
        String ids = prefs.getString("downloadIds", "").trim();
        if (ids.isEmpty()) return "No owned download IDs.";
        DownloadManager manager = getSystemService(DownloadManager.class);
        StringBuilder report = new StringBuilder();
        for (String value : ids.split("\\s+")) {
            long id = Long.parseLong(value);
            report.append("ID=").append(id);
            try (Cursor cursor = manager.query(new DownloadManager.Query().setFilterById(id))) {
                if (cursor == null || !cursor.moveToFirst()) {
                    report.append(" MISSING\n");
                    continue;
                }
                int status = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS));
                int reason = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON));
                report.append(" status=").append(downloadState(status))
                        .append("(").append(status).append("); reason=").append(reason)
                        .append("\nlocalURI=").append(cursor.getString(
                                cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_LOCAL_URI)));
                if (status == DownloadManager.STATUS_SUCCESSFUL) {
                    try (ParcelFileDescriptor descriptor = manager.openDownloadedFile(id);
                            InputStream stream = new ParcelFileDescriptor.AutoCloseInputStream(descriptor)) {
                        report.append("\n").append(digest(stream, false));
                    }
                } else {
                    report.append("\nSHA256=unavailable (not completed successfully)");
                }
            }
            report.append("\n");
        }
        return report.toString();
    }

    private static String downloadState(int status) {
        switch (status) {
            case DownloadManager.STATUS_PENDING: return "PENDING";
            case DownloadManager.STATUS_RUNNING: return "RUNNING";
            case DownloadManager.STATUS_PAUSED: return "PAUSED";
            case DownloadManager.STATUS_SUCCESSFUL: return "SUCCESSFUL";
            case DownloadManager.STATUS_FAILED: return "FAILED";
            default: return "UNKNOWN";
        }
    }

    private String permissionState() {
        return checkSelfPermission(Manifest.permission.READ_CONTACTS)
                == PackageManager.PERMISSION_GRANTED ? "GRANTED" : "DENIED";
    }

    private String queryContacts() {
        String permission = "READ_CONTACTS=" + permissionState();
        // Deliberately query even when denied, to observe the real provider contract.
        // Only _ID is projected; no rows or values are ever read.
        try (Cursor cursor = getContentResolver().query(ContactsContract.Contacts.CONTENT_URI,
                new String[] { ContactsContract.Contacts._ID }, null, null, null)) {
            if (cursor == null) return permission + "; API=NULL_CURSOR";
            return permission + "; API=SUCCESS; count=" + cursor.getCount();
        } catch (SecurityException e) {
            return permission + "; API=SecurityException";
        } catch (RuntimeException e) {
            return permission + "; API=ERROR:" + e.getClass().getSimpleName();
        }
    }

    @Override public void onRequestPermissionsResult(int request, String[] permissions, int[] grants) {
        super.onRequestPermissionsResult(request, permissions, grants);
        if (request == CONTACTS) {
            contactsStatus.setText("READ_CONTACTS=" + permissionState()
                    + "; callback=" + (grants.length == 0 ? "CANCELLED" : "RECEIVED")
                    + "; API not queried (use separate button).");
        }
    }

    private interface Operation { String run() throws Exception; }

    private void runIo(TextView output, Operation operation) {
        output.setText("RUNNING");
        io.execute(() -> {
            String result;
            try {
                result = operation.run();
            } catch (Exception e) {
                result = "ERROR=" + e.getClass().getSimpleName()
                        + "; operation incomplete; see owned-artifact ledger.";
            }
            final String report = result;
            runOnUiThread(() -> output.setText(report));
        });
    }

    private synchronized void record(String entry) {
        String ledger = prefs.getString("ledger", "");
        String updated = ledger + entry + "\n";
        prefs.edit().putString("ledger", updated).commit();
        runOnUiThread(() -> ownership.setText(updated));
    }

    private static String digest(InputStream stream, boolean compareMarker) throws Exception {
        MessageDigest hash = MessageDigest.getInstance("SHA-256");
        byte[] buffer = new byte[8192];
        long count = 0;
        boolean matches = true;
        int size;
        while ((size = stream.read(buffer)) != -1) {
            hash.update(buffer, 0, size);
            if (compareMarker) {
                for (int i = 0; i < size; i++) {
                    if (count + i >= MARKER.length || buffer[i] != MARKER[(int) (count + i)]) {
                        matches = false;
                    }
                }
            }
            count += size;
        }
        return "bytes=" + count + "; SHA256=" + hex(hash.digest())
                + (compareMarker ? "; marker=" + (matches && count == MARKER.length ? "MATCH" : "MISMATCH") : "");
    }

    private static String hex(byte[] bytes) {
        StringBuilder value = new StringBuilder();
        for (byte b : bytes) value.append(String.format(Locale.ROOT, "%02x", b & 255));
        return value.toString();
    }

    @Override protected void onSaveInstanceState(Bundle state) {
        state.putString("pendingName", pendingName);
        super.onSaveInstanceState(state);
    }

    @Override protected void onDestroy() {
        imeStatus.removeCallbacks(imeUpdate);
        io.shutdown();
        super.onDestroy();
    }
}
