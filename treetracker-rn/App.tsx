import React, { useEffect, useState } from "react";
import { ActivityIndicator, View } from "react-native";
import { NavigationContainer, DefaultTheme } from "@react-navigation/native";
import { createNativeStackNavigator } from "@react-navigation/native-stack";
import { SafeAreaProvider } from "react-native-safe-area-context";
import { StatusBar } from "expo-status-bar";

import { RootStackParamList } from "./src/navigation";
import { loadState, getState } from "./src/store";

import LanguageScreen from "./src/screens/LanguageScreen";
import CredentialScreen from "./src/screens/CredentialScreen";
import NameScreen from "./src/screens/NameScreen";
import SelfieScreen from "./src/screens/SelfieScreen";
import ImageReviewScreen from "./src/screens/ImageReviewScreen";
import DashboardScreen from "./src/screens/DashboardScreen";
import UserSelectScreen from "./src/screens/UserSelectScreen";
import WalletSelectScreen from "./src/screens/WalletSelectScreen";
import AddOrgScreen from "./src/screens/AddOrgScreen";
import TreeCaptureScreen from "./src/screens/TreeCaptureScreen";
import TreeImageReviewScreen from "./src/screens/TreeImageReviewScreen";

const Stack = createNativeStackNavigator<RootStackParamList>();

export default function App() {
  const [ready, setReady] = useState(false);
  const [hasUser, setHasUser] = useState(false);

  useEffect(() => {
    loadState().then(() => {
      setHasUser(getState().users.length > 0);
      setReady(true);
    });
  }, []);

  if (!ready) {
    return (
      <View
        style={{
          flex: 1,
          alignItems: "center",
          justifyContent: "center",
          backgroundColor: "#191C1F",
        }}>
        <ActivityIndicator color="#75B926" />
      </View>
    );
  }

  const navTheme = {
    ...DefaultTheme,
    colors: { ...DefaultTheme.colors, background: "#191C1F" },
  };

  return (
    <SafeAreaProvider>
      <StatusBar style="light" />
      <NavigationContainer theme={navTheme}>
        <Stack.Navigator
          initialRouteName={hasUser ? "Dashboard" : "Language"}
          screenOptions={{ headerShown: false, animation: "none" }}>
          <Stack.Screen name="Language" component={LanguageScreen} />
          <Stack.Screen name="Credential" component={CredentialScreen} />
          <Stack.Screen name="Name" component={NameScreen} />
          <Stack.Screen name="Selfie" component={SelfieScreen} />
          <Stack.Screen name="ImageReview" component={ImageReviewScreen} />
          <Stack.Screen name="Dashboard" component={DashboardScreen} />
          <Stack.Screen name="UserSelect" component={UserSelectScreen} />
          <Stack.Screen name="WalletSelect" component={WalletSelectScreen} />
          <Stack.Screen name="AddOrg" component={AddOrgScreen} />
          <Stack.Screen name="TreeCapture" component={TreeCaptureScreen} />
          <Stack.Screen name="TreeImageReview" component={TreeImageReviewScreen} />
        </Stack.Navigator>
      </NavigationContainer>
    </SafeAreaProvider>
  );
}
