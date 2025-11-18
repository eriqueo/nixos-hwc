#!/usr/bin/env python3
"""
Performance test script for n8n workflows database
"""
import sqlite3
import time
import os

def test_performance():
    """Test database performance metrics"""
    
    # Check if database exists
    if not os.path.exists('workflows.db'):
        print("❌ Database not found. Run 'python run.py --reindex' first.")
        return
    
    conn = sqlite3.connect('workflows.db')
    cursor = conn.cursor()
    
    print("🚀 Testing Database Performance...")
    print("=" * 50)
    
    # Test 1: Basic count query
    start_time = time.time()
    cursor.execute('SELECT COUNT(*) FROM workflows')
    count = cursor.fetchone()[0]
    basic_time = (time.time() - start_time) * 1000
    
    # Test 2: FTS search
    start_time = time.time()
    try:
        cursor.execute('SELECT * FROM workflows_fts WHERE workflows_fts MATCH "telegram" LIMIT 10')
        results = cursor.fetchall()
        fts_time = (time.time() - start_time) * 1000
        fts_success = True
    except Exception as e:
        fts_time = 0
        fts_success = False
        fts_error = str(e)
    
    # Test 3: Complex query with filters
    start_time = time.time()
    cursor.execute('SELECT * FROM workflows WHERE trigger_type = "Webhook" AND complexity = "medium" LIMIT 20')
    results = cursor.fetchall()
    complex_time = (time.time() - start_time) * 1000
    
    # Test 4: Category-based query
    start_time = time.time()
    cursor.execute('SELECT * FROM workflows WHERE category = "Communication & Messaging" LIMIT 20')
    results = cursor.fetchall()
    category_time = (time.time() - start_time) * 1000
    
    # Test 5: Full table scan
    start_time = time.time()
    cursor.execute('SELECT filename, name, trigger_type FROM workflows LIMIT 100')
    results = cursor.fetchall()
    scan_time = (time.time() - start_time) * 1000
    
    conn.close()
    
    # Results
    print(f"📊 Performance Results:")
    print(f"   Total Workflows: {count:,}")
    print(f"   Basic Query: {basic_time:.2f}ms")
    print(f"   FTS Search: {fts_time:.2f}ms {'✅' if fts_success else '❌'}")
    if not fts_success:
        print(f"   FTS Error: {fts_error}")
    print(f"   Complex Query: {complex_time:.2f}ms")
    print(f"   Category Query: {category_time:.2f}ms")
    print(f"   Table Scan: {scan_time:.2f}ms")
    
    print("\n🎯 Performance Analysis:")
    print("=" * 50)
    
    # Performance assessment
    if basic_time < 10:
        print("✅ Basic queries: EXCELLENT (<10ms)")
    elif basic_time < 50:
        print("✅ Basic queries: GOOD (<50ms)")
    else:
        print("⚠️  Basic queries: NEEDS OPTIMIZATION (>50ms)")
    
    if fts_success:
        if fts_time < 50:
            print("✅ FTS search: EXCELLENT (<50ms)")
        elif fts_time < 100:
            print("✅ FTS search: GOOD (<100ms)")
        else:
            print("⚠️  FTS search: NEEDS OPTIMIZATION (>100ms)")
    else:
        print("❌ FTS search: NOT WORKING")
    
    if complex_time < 50:
        print("✅ Complex queries: EXCELLENT (<50ms)")
    elif complex_time < 100:
        print("✅ Complex queries: GOOD (<100ms)")
    else:
        print("⚠️  Complex queries: NEEDS OPTIMIZATION (>100ms)")
    
    # Overall assessment
    avg_time = (basic_time + (fts_time if fts_success else 0) + complex_time) / (3 if fts_success else 2)
    print(f"\n📈 Average Response Time: {avg_time:.2f}ms")
    
    if avg_time < 50:
        print("🎉 OVERALL: EXCELLENT PERFORMANCE!")
        print("   Your database is performing optimally.")
    elif avg_time < 100:
        print("✅ OVERALL: GOOD PERFORMANCE")
        print("   Database is performing well, minor optimizations possible.")
    else:
        print("⚠️  OVERALL: NEEDS OPTIMIZATION")
        print("   Consider database optimization techniques.")
    
    # Recommendations
    print("\n💡 Optimization Recommendations:")
    print("=" * 50)
    
    if not fts_success:
        print("1. 🔧 Fix FTS search - Check workflows_fts table creation")
    
    if basic_time > 50:
        print("2. 📊 Add indexes on frequently queried columns")
    
    if complex_time > 100:
        print("3. 🔍 Optimize complex queries with better indexing")
    
    if avg_time > 100:
        print("4. 🚀 Consider database tuning and query optimization")
    
    if avg_time < 50:
        print("✅ No optimization needed - performance is excellent!")

if __name__ == "__main__":
    test_performance()
