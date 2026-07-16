import React, { useState } from "react";
import { Image, Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
import { useNavigation } from "@react-navigation/native";
import { ActionBar } from "../components/ActionBar";
import { Screen } from "../components/Layout";
import { OrangeAddButton } from "../components/DepthButton";
import { AppColors, Fonts, TextColors } from "../theme";
import { Nav } from "../navigation";
import { useStore } from "../store";

export default function UserSelectScreen() {
  const nav = useNavigation<Nav<"UserSelect">>();
  const users = useStore((s) => s.users);
  const [selected, setSelected] = useState<string | null>(
    users[0]?.uuid ?? null,
  );

  return (
    <Screen>
      <ScrollView contentContainerStyle={styles.grid}>
        {users.map((u) => {
          const name = `${u.firstName} ${u.lastName}`.trim();
          const sel = selected === u.uuid;
          return (
            <Pressable
              key={u.uuid}
              onPress={() => setSelected(u.uuid)}
              style={[styles.card, sel && styles.cardSel]}>
              {u.photoPath ? (
                <Image source={{ uri: u.photoPath }} style={styles.photo} />
              ) : (
                <View style={[styles.photo, styles.photoPlaceholder]} />
              )}
              <Text numberOfLines={1} style={styles.name}>
                {name}
              </Text>
              <Text numberOfLines={1} style={styles.wallet}>
                {u.wallet}
              </Text>
            </Pressable>
          );
        })}
      </ScrollView>
      <ActionBar
        onBack={() => nav.navigate("Dashboard")}
        center={<OrangeAddButton onPress={() => {}} />}
        forwardEnabled={!!selected}
        onForward={() =>
          selected && nav.navigate("WalletSelect", { userUuid: selected })
        }
      />
    </Screen>
  );
}

const styles = StyleSheet.create({
  grid: {
    flexDirection: "row",
    flexWrap: "wrap",
    padding: 8,
    paddingTop: 16,
  },
  card: {
    width: "46%",
    margin: "2%",
    backgroundColor: AppColors.GrayShadow,
    borderRadius: 10,
    padding: 8,
    borderWidth: 1,
    borderColor: "transparent",
  },
  cardSel: { borderColor: AppColors.Green },
  photo: {
    width: "100%",
    aspectRatio: 1,
    borderRadius: 10,
    marginBottom: 8,
  },
  photoPlaceholder: { backgroundColor: AppColors.DeepGray },
  name: {
    color: TextColors.lightText,
    fontSize: 12,
    fontWeight: "600",
    fontFamily: Fonts.regular,
    paddingHorizontal: 4,
  },
  wallet: {
    color: TextColors.lightText,
    fontSize: 12,
    fontWeight: "600",
    fontFamily: Fonts.regular,
    paddingHorizontal: 4,
  },
});
