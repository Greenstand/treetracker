import React, { useState } from "react";
import { Pressable, StyleSheet, Text, View } from "react-native";
import { useNavigation } from "@react-navigation/native";
import { S } from "../strings";
import { Nav } from "../navigation";
import { readyToUpload, uploadedCount, useStore } from "../store";
import { uploadPending } from "../upload";

export default function DashboardScreen() {
  const nav = useNavigation<Nav<"Dashboard">>();
  // re-render on store changes
  useStore((s) => s.captures.length + s.uploadedCount);
  const ready = readyToUpload();
  const uploaded = uploadedCount();
  const [uploading, setUploading] = useState(false);

  async function onUpload() {
    if (uploading) return;
    setUploading(true);
    try {
      await uploadPending();
    } catch (e) {
      // eslint-disable-next-line no-console
      console.warn("upload failed", e);
    } finally {
      setUploading(false);
    }
  }

  return (
    <View style={styles.root}>
      <View style={styles.counts}>
        <View style={styles.countBox}>
          <Text accessibilityLabel={S.treesReadyToUpload} style={styles.count}>
            {String(ready)}
          </Text>
          <Text style={styles.countCaption}>{S.treesReadyToUpload}</Text>
        </View>
        <View style={styles.countBox}>
          <Text accessibilityLabel={S.treesUploaded} style={styles.count}>
            {String(uploaded)}
          </Text>
          <Text style={styles.countCaption}>{S.treesUploaded}</Text>
        </View>
      </View>

      <View style={styles.buttons}>
        <Pressable style={styles.btn} onPress={onUpload}>
          <Text style={styles.btnText}>{S.upload}</Text>
        </Pressable>
        <Pressable style={styles.btn} onPress={() => {}}>
          <Text style={styles.btnText}>{S.messages}</Text>
        </Pressable>
        <Pressable
          style={[styles.btn, styles.track]}
          onPress={() => nav.navigate("UserSelect")}>
          <Text style={styles.btnText}>{S.track}</Text>
        </Pressable>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: "#fff", padding: 24, paddingTop: 60 },
  counts: { flexDirection: "row", justifyContent: "space-around", marginBottom: 40 },
  countBox: { alignItems: "center" },
  count: { fontSize: 40, fontWeight: "800", color: "#1B5E20" },
  countCaption: { fontSize: 13, color: "#555" },
  buttons: { gap: 18, alignItems: "center" },
  btn: {
    width: "80%",
    paddingVertical: 22,
    borderRadius: 12,
    backgroundColor: "#2E7D32",
    alignItems: "center",
  },
  track: { backgroundColor: "#1B5E20" },
  btnText: { color: "#fff", fontSize: 22, fontWeight: "700" },
});
