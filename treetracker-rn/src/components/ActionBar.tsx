import React from "react";
import { StyleSheet, View } from "react-native";
import { ArrowButton } from "./DepthButton";
import { ButtonColors, DepthColors } from "../theme";

type Props = {
  onBack?: () => void;
  onForward?: () => void;
  backEnabled?: boolean;
  forwardEnabled?: boolean;
  center?: React.ReactNode;
  arrowColors?: DepthColors;
};

// Bottom action bar (Android ActionBar: 80dp, three equal cells). Back arrow on
// the left, optional center action, forward arrow on the right. The arrows are
// DepthButtons whose accessibilityLabel -> content-desc drives the e2e selectors
// ("Navigate forward" / "Navigate back").
export function ActionBar({
  onBack,
  onForward,
  backEnabled = true,
  forwardEnabled = true,
  center,
  arrowColors = ButtonColors.ProgressGreen,
}: Props) {
  return (
    <View style={styles.bar}>
      <View style={styles.cell}>
        {onBack ? (
          <ArrowButton
            isLeft
            onPress={onBack}
            enabled={backEnabled}
            colors={arrowColors}
          />
        ) : null}
      </View>
      <View style={[styles.cell, styles.center]}>{center}</View>
      <View style={[styles.cell, styles.right]}>
        {onForward ? (
          <ArrowButton
            isLeft={false}
            onPress={onForward}
            enabled={forwardEnabled}
            colors={arrowColors}
          />
        ) : null}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  bar: {
    flexDirection: "row",
    alignItems: "center",
    height: 80,
    paddingHorizontal: 4,
  },
  cell: { flex: 1, justifyContent: "center" },
  center: { alignItems: "center" },
  right: { alignItems: "flex-end" },
});
