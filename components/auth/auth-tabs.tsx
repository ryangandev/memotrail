import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';

import LoginForm from './login-form';
import SignupForm from './signup-form';

export default function AuthTabs() {
  return (
    <Tabs defaultValue="login" className="w-[400px]">
      <TabsList className="grid w-full grid-cols-2">
        <TabsTrigger value="login">Log in</TabsTrigger>
        <TabsTrigger value="signup">Sign up</TabsTrigger>
      </TabsList>
      <TabsContent value="login">
        <LoginForm />
      </TabsContent>
      <TabsContent value="signup">
        <SignupForm />
      </TabsContent>
    </Tabs>
  );
}
