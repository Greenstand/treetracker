import React from "react";
import { Image, StyleSheet, View, ViewStyle, StyleProp } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { AppColors } from "../theme";

// Dark screen wrapper matching the Android Scaffold (AppColors.Gray background).
export function Screen({
  children,
  style,
}: {
  children: React.ReactNode;
  style?: StyleProp<ViewStyle>;
}) {
  return (
    <SafeAreaView style={styles.root} edges={["top", "bottom"]}>
      <View style={[styles.fill, style]}>{children}</View>
    </SafeAreaView>
  );
}

// Top action bar (80dp) with the Greenstand logo centered; optional left/right.
export function TopBar({
  left,
  right,
}: {
  left?: React.ReactNode;
  right?: React.ReactNode;
}) {
  return (
    <View style={styles.topBar}>
      <View style={styles.cell}>{left}</View>
      <View style={[styles.cell, styles.center]}>
        <Image
          source={require("../../assets/logo.png")}
          style={styles.logo}
          resizeMode="contain"
          accessibilityLabel="Treetracker icon"
        />
      </View>
      <View style={[styles.cell, styles.right]}>{right}</View>
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: AppColors.Gray },
  fill: { flex: 1, backgroundColor: AppColors.Gray },
  topBar: {
    flexDirection: "row",
    alignItems: "center",
    height: 80,
    paddingHorizontal: 4,
  },
  cell: { flex: 1, justifyContent: "center" },
  center: { alignItems: "center" },
  right: { alignItems: "flex-end" },
  logo: { width: 64, height: 80 },
});
