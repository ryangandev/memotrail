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
import { SignupSchema } from '@/schemas/auth-schema';
import { signup } from '@/actions/auth-actions';
import { toast } from 'sonner';
import { useForm } from 'react-hook-form';
import { z } from 'zod';
import { zodResolver } from '@hookform/resolvers/zod';

export default function SignupForm() {
  const {
    handleSubmit,
    register,
    formState: { errors, isSubmitting },
    reset,
  } = useForm<z.infer<typeof SignupSchema>>({
    resolver: zodResolver(SignupSchema),
    defaultValues: {
      email: '',
      password: '',
    },
  });

  const onSubmit = async (data: z.infer<typeof SignupSchema>) => {
    const response = await signup(data);
    if (response.error) {
      toast.error(response.error);
    }

    if (response.success) {
      toast.success(response.message);
      reset();
    }
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle>Sign up to MemoTrail</CardTitle>
      </CardHeader>
      <CardContent className="space-y-2">
        <form
          id="signup-form"
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
        <Button form="signup-form" type="submit" disabled={isSubmitting}>
          Sign up
        </Button>
      </CardFooter>
    </Card>
  );
}
