import React, { useState } from "react";
import { StyleSheet, Text, View } from "react-native";
import { useNavigation } from "@react-navigation/native";
import { Screen, TopBar } from "../components/Layout";
import { DepthButton, DepthTextButton } from "../components/DepthButton";
import { AppColors, ButtonColors, Fonts, TextColors } from "../theme";
import { S } from "../strings";
import { Nav } from "../navigation";
import { readyToUpload, uploadedCount, useStore } from "../store";
import { uploadPending } from "../upload";

export default function DashboardScreen() {
  const nav = useNavigation<Nav<"Dashboard">>();
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

  const langButton = (
    <DepthTextButton
      label="ENGLISH"
      width={120}
      height={50}
      onPress={() => nav.navigate("Language")}
    />
  );

  return (
    <Screen>
      <TopBar right={langButton} />

      {/* Trees uploaded counter */}
      <View style={styles.counterRow}>
        <Text style={styles.leaf}>🌿</Text>
        <Text
          accessibilityLabel={S.treesUploaded}
          style={styles.uploadedCount}>
          {String(uploaded)}
        </Text>
      </View>

      {/* Upload progress + UPLOAD button */}
      <View style={styles.uploadRow}>
        <View style={styles.progressCol}>
          <View style={styles.ring}>
            <Text
              accessibilityLabel={S.treesReadyToUpload}
              style={styles.readyCount}>
              {String(ready)}
            </Text>
          </View>
        </View>
        <View style={styles.uploadBtnCol}>
          <DepthButton
            circle
            colors={ButtonColors.UploadOrange}
            width={130}
            height={130}
            depth={10}
            onPress={onUpload}>
            <Text style={styles.uploadLabel}>{S.upload}</Text>
          </DepthButton>
        </View>
      </View>

      {/* MESSAGES */}
      <DepthButton
        colors={ButtonColors.MessagePurple}
        style={styles.bigBtn}
        onPress={() => {}}>
        <Text style={styles.bigLabel}>{S.messages}</Text>
      </DepthButton>

      {/* TRACK */}
      <DepthButton
        colors={ButtonColors.ProgressGreen}
        style={[styles.bigBtn, styles.bigBtnBottom]}
        onPress={() => nav.navigate("UserSelect")}>
        <Text style={styles.bigLabel}>{S.track}</Text>
      </DepthButton>
    </Screen>
  );
}

const styles = StyleSheet.create({
  counterRow: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
    paddingVertical: 10,
  },
  leaf: { fontSize: 26, marginRight: 8 },
  uploadedCount: {
    color: TextColors.uploadText,
    fontSize: 24,
    fontWeight: "bold",
    fontFamily: Fonts.bold,
  },
  uploadRow: {
    flexDirection: "row",
    paddingHorizontal: 20,
    paddingVertical: 10,
    alignItems: "center",
  },
  progressCol: { flex: 1, alignItems: "center" },
  ring: {
    width: 110,
    height: 110,
    borderRadius: 55,
    borderWidth: 8,
    borderColor: AppColors.Orange,
    alignItems: "center",
    justifyContent: "center",
  },
  readyCount: {
    color: TextColors.lightText,
    fontSize: 24,
    fontFamily: Fonts.regular,
  },
  uploadBtnCol: { flex: 1, alignItems: "center" },
  uploadLabel: {
    color: TextColors.darkText,
    fontSize: 16,
    fontWeight: "bold",
    fontFamily: Fonts.bold,
  },
  bigBtn: {
    flex: 1,
    marginHorizontal: 20,
    marginVertical: 10,
  },
  bigBtnBottom: { marginBottom: 20 },
  bigLabel: {
    color: TextColors.darkText,
    fontSize: 16,
    fontWeight: "bold",
    fontFamily: Fonts.bold,
  },
});
