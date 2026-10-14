CREATE TABLE "turns" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"session_id" uuid NOT NULL,
	"status" "session_status" DEFAULT 'UPLOADED' NOT NULL,
	"recording_key" text NOT NULL,
	"user_text" text,
	"agent_text" text,
	"audio_key" text,
	"crisis" boolean DEFAULT false NOT NULL,
	"closing" boolean DEFAULT false NOT NULL,
	"error" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "sessions" ADD COLUMN "crisis" boolean DEFAULT false NOT NULL;--> statement-breakpoint
ALTER TABLE "users" ADD COLUMN "profile" text;--> statement-breakpoint
ALTER TABLE "users" ADD COLUMN "profile_updated_at" timestamp with time zone;--> statement-breakpoint
ALTER TABLE "turns" ADD CONSTRAINT "turns_session_id_sessions_id_fk" FOREIGN KEY ("session_id") REFERENCES "public"."sessions"("id") ON DELETE cascade ON UPDATE no action;