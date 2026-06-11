import React from "react";
import { Pressable, Text, View, StyleSheet } from "react-native";
import { S } from "../strings";

type Props = {
  onBack?: () => void;
  onForward?: () => void;
  forwardEnabled?: boolean;
};

// Bottom action bar with back (left) and forward (right) arrows. Each arrow
// exposes an accessibilityLabel -> Android content-desc so the e2e can target
// it via UiSelector().description("Navigate forward" / "Navigate back").
export function ActionBar({ onBack, onForward, forwardEnabled = true }: Props) {
  return (
    <View style={styles.bar}>
      <Pressable
        accessibilityLabel={S.navigateBack}
        accessibilityRole="button"
        onPress={onBack}
        disabled={!onBack}
        style={styles.btn}>
        <Text style={styles.arrow}>{"‹"}</Text>
      </Pressable>
      <View style={{ flex: 1 }} />
      <Pressable
        accessibilityLabel={S.navigateForward}
        accessibilityRole="button"
        accessibilityState={{ disabled: !forwardEnabled }}
        onPress={forwardEnabled ? onForward : undefined}
        disabled={!forwardEnabled}
        style={[styles.btn, !forwardEnabled && styles.disabled]}>
        <Text style={styles.arrow}>{"›"}</Text>
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  bar: {
    flexDirection: "row",
    alignItems: "center",
    paddingHorizontal: 24,
    paddingVertical: 16,
    backgroundColor: "#2E7D32",
  },
  btn: {
    width: 56,
    height: 56,
    borderRadius: 28,
    backgroundColor: "#1B5E20",
    alignItems: "center",
    justifyContent: "center",
  },
  disabled: { opacity: 0.4 },
  arrow: { color: "#fff", fontSize: 30, fontWeight: "bold" },
});
