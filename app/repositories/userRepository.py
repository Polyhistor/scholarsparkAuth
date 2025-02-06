from typing import Optional, Dict
from ..schema.user import User, UserResponse, UserCreate, UserProfileCreate
from ..core.securityUtils import get_password_hash
from ..core.config import settings
from scholarSparkObservability.core import OTelSetup
import psycopg2
from psycopg2.extras import RealDictCursor


class UserRepository:
    def __init__(self):
        self.otel = OTelSetup.get_instance()

    @staticmethod
    def get_connection():
        otel = OTelSetup.get_instance()
        with otel.create_span("get_db_connection", {
            "db.system": "postgresql"
        }) as span:
            try:
                conn = psycopg2.connect(
                    settings.DATABASE_URL,
                    cursor_factory=RealDictCursor
                )
                return conn
            except Exception as e:
                otel.record_exception(span, e)
                raise

    def create_user(self, user: UserCreate, profile: UserProfileCreate) -> Optional[Dict]:
        with self.otel.create_span("create_user", {
            "user.email": user.email
        }) as span:
            try:
                conn = self.get_connection()
                with conn:
                    with conn.cursor() as cur:
                        # Create user with status flags
                        cur.execute(
                            """
                            INSERT INTO users (
                                email, 
                                password_hash, 
                                is_active,
                                is_deleted
                            )
                            VALUES (%s, %s, %s, %s)
                            RETURNING 
                                user_id, 
                                email, 
                                is_active,
                                is_deleted,
                                created_at, 
                                updated_at;
                            """,
                            (
                                user.email,
                                get_password_hash(user.password),
                                user.is_active,
                                user.is_deleted
                            )
                        )
                        user_result = cur.fetchone()
                        span.set_attributes({"user.id": user_result["user_id"]})
                        return user_result
            except psycopg2.Error as e:
                self.otel.record_exception(span, e)
                raise
            finally:
                conn.close()

    def get_by_email(self, email: str) -> Optional[Dict]:
        conn = None
        with self.otel.create_span("get_user_by_email", {
            "user.email": email
        }) as span:
            try:
                conn = self.get_connection()
                with conn:
                    with conn.cursor() as cur:
                        cur.execute(
                            """
                            SELECT id, email, hashed_password, is_active 
                            FROM users 
                            WHERE email = %s;
                            """,
                            (email,)
                        )
                        result = cur.fetchone()
                        if result:
                            span.set_attributes({"user.id": result["id"]})
                        return result
            except psycopg2.Error as e:
                self.otel.record_exception(span, e)
                raise
            finally:
                if conn is not None:
                    conn.close()

    def soft_delete_user(self, user_id: int) -> bool:
        """Soft delete a user by setting is_deleted to True"""
        with self.otel.create_span("soft_delete_user", {
            "user.id": user_id
        }) as span:
            try:
                conn = self.get_connection()
                with conn:
                    with conn.cursor() as cur:
                        cur.execute(
                            """
                            UPDATE users 
                            SET 
                                is_deleted = TRUE,
                                is_active = FALSE,
                                updated_at = CURRENT_TIMESTAMP
                            WHERE user_id = %s
                            RETURNING user_id;
                            """,
                            (user_id,)
                        )
                        return cur.fetchone() is not None
            except Exception as e:
                self.otel.record_exception(span, e)
                raise

    def update_user_status(self, user_id: int, is_active: bool) -> Optional[Dict]:
        """Update user's active status"""
        with self.otel.create_span("update_user_status", {
            "user.id": user_id
        }) as span:
            try:
                conn = self.get_connection()
                with conn:
                    with conn.cursor() as cur:
                        cur.execute(
                            """
                            UPDATE users 
                            SET 
                                is_active = %s,
                                updated_at = CURRENT_TIMESTAMP
                            WHERE 
                                user_id = %s 
                                AND is_deleted = FALSE
                            RETURNING 
                                user_id, 
                                email, 
                                is_active,
                                is_deleted,
                                updated_at;
                            """,
                            (is_active, user_id)
                        )
                        return cur.fetchone()
            except Exception as e:
                self.otel.record_exception(span, e)
                raise

    def get_user_by_email(self, email: str) -> Optional[Dict]:
        """Get user by email, excluding soft-deleted users"""
        with self.otel.create_span("get_user", {
            "user.email": email
        }) as span:
            try:
                conn = self.get_connection()
                with conn:
                    with conn.cursor() as cur:
                        cur.execute(
                            """
                            SELECT u.*, p.*
                            FROM users u
                            LEFT JOIN user_profiles p ON u.user_id = p.user_id
                            WHERE 
                                u.email = %s 
                                AND u.is_deleted = FALSE;
                            """,
                            (email,)
                        )
                        return cur.fetchone()
            except Exception as e:
                self.otel.record_exception(span, e)
                raise