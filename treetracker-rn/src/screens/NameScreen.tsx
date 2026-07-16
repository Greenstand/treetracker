import React, { useState } from "react";
import { StyleSheet, View } from "react-native";
import { useNavigation } from "@react-navigation/native";
import { ActionBar } from "../components/ActionBar";
import { Screen, TopBar } from "../components/Layout";
import { DepthTextButton } from "../components/DepthButton";
import { BorderedTextField } from "../components/BorderedTextField";
import { S } from "../strings";
import { Nav } from "../navigation";
import { setSignupName } from "../signupDraft";

// Name entry. EditText[0] = first name, EditText[1] = last name.
export default function NameScreen() {
  const nav = useNavigation<Nav<"Name">>();
  const [first, setFirst] = useState("");
  const [last, setLast] = useState("");

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
      <View style={styles.body}>
        <BorderedTextField
          style={styles.input}
          placeholder={S.firstName}
          autoCorrect={false}
          value={first}
          onChangeText={setFirst}
        />
        <BorderedTextField
          style={styles.input}
          placeholder={S.lastName}
          autoCorrect={false}
          value={last}
          onChangeText={setLast}
        />
      </View>
      <ActionBar
        onBack={() => nav.goBack()}
        forwardEnabled={first.trim().length > 0 && last.trim().length > 0}
        onForward={() => {
          setSignupName(first.trim(), last.trim());
          nav.navigate("Selfie");
        }}
      />
    </Screen>
  );
}

const styles = StyleSheet.create({
  body: { flex: 1, justifyContent: "center" },
  input: { marginHorizontal: 4, marginVertical: 4 },
});
