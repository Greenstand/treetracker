import React, { useState } from "react";
import { Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
import { useNavigation } from "@react-navigation/native";
import { ActionBar } from "../components/ActionBar";
import { Nav } from "../navigation";
import { useStore } from "../store";

export default function UserSelectScreen() {
  const nav = useNavigation<Nav<"UserSelect">>();
  const users = useStore((s) => s.users);
  const [selected, setSelected] = useState<string | null>(
    users[0]?.uuid ?? null,
  );

  return (
    <View style={styles.root}>
      <ScrollView contentContainerStyle={styles.list}>
        {users.map((u) => {
          const name = `${u.firstName} ${u.lastName}`.trim();
          return (
            <Pressable
              key={u.uuid}
              onPress={() => setSelected(u.uuid)}
              style={[styles.card, selected === u.uuid && styles.cardSel]}>
              <Text style={styles.name}>{name}</Text>
            </Pressable>
          );
        })}
      </ScrollView>
      <ActionBar
        onBack={() => nav.navigate("Dashboard")}
        forwardEnabled={!!selected}
        onForward={() =>
          selected && nav.navigate("WalletSelect", { userUuid: selected })
        }
      />
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: "#fff" },
  list: { padding: 24, paddingTop: 60, gap: 16 },
  card: {
    padding: 24,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: "#2E7D32",
    alignItems: "center",
  },
  cardSel: { backgroundColor: "#C8E6C9" },
  name: { fontSize: 20, fontWeight: "600", color: "#1B5E20" },
});
