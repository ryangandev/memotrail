'use client';

import {
  Card,
  CardContent,
  CardFooter,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';

import AuthError from './auth-error';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { LoginSchema } from '@/schemas/auth-schema';
import { login } from '@/actions/auth-actions';
import { toast } from 'sonner';
import { useForm } from 'react-hook-form';
import { z } from 'zod';
import { zodResolver } from '@hookform/resolvers/zod';

export default function LoginForm() {
  const {
    handleSubmit,
    register,
    formState: { errors, isSubmitting },
  } = useForm<z.infer<typeof LoginSchema>>({
    resolver: zodResolver(LoginSchema),
    defaultValues: {
      email: '',
      password: '',
    },
  });

  const onSubmit = async (data: z.infer<typeof LoginSchema>) => {
    const response = await login(data);
    if (response.error) {
      toast.error(response.error);
    }

    // If login is successful, redirect to the lessons page will happen in the login action
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle>Log in to MemoTrail</CardTitle>
      </CardHeader>
      <CardContent className="space-y-2">
        <form
          id="login-form"
          onSubmit={handleSubmit(onSubmit)}
          className="space-y-4"
        >
          <div className="space-y-2">
            <Label htmlFor="email">Email</Label>
            <Input
              {...register('email')}
              id="email"
              type="email"
              placeholder="Enter email"
            />
            <AuthError message={errors.email?.message} />
          </div>
          <div className="space-y-2">
            <Label htmlFor="password">Password</Label>
            <Input
              {...register('password')}
              id="password"
              type="password"
              placeholder="Enter password"
            />
            <AuthError message={errors.password?.message} />
          </div>
        </form>
      </CardContent>
      <CardFooter>
        <Button type="submit" form="login-form" disabled={isSubmitting}>
          Log in
        </Button>
      </CardFooter>
    </Card>
  );
}
